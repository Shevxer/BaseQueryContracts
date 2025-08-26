// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IReputationSystem {
    enum ContentType { QUESTION, ANSWER }
    
    function canAnswer(address user) external view returns (bool);
    function canVote(address user) external view returns (bool);
    function vote(uint256 questionId, uint256 answerId, ContentType contentType, bool isUpvote, address contentOwner, address voter) external;
    function updateReputation(address user, int256 change) external;
    function getVoteCount(uint256 questionId, uint256 answerId, ContentType contentType) external view returns (uint256, uint256);
    function getUserReputation(address user) external view returns (uint256, uint256);
}

contract BaseQuery is Ownable {
    error QuestionNotFound();
    error AnswerNotFound();
    error NotQuestionOwner();
    error CannotAnswer();
    error InsufficientBounty();
    error AlreadyAnswered();
    error PoolNotExpired();
    error PoolExpired();
    error NoAnswers();
    error TransferFailed();
    error BestAnswerAlreadySelected();
    error InvalidPoolDuration();
    error USDCTransferFailed();
    error CannotWithdrawWithGoodAnswers();
    error CannotWithdrawBountyWithAnswers();
    error BountyAlreadyDistributed();

    struct Question {
        uint256 id;
        address owner;
        string ipfsHash;
        uint256 bountyAmount;    // USDC amount
        uint256 poolAmount;      // USDC amount
        uint256 poolEndTime;
        uint256 selectedAnswerId;
        uint256[] answerIds;
        bool poolDistributed;
        bool isActive;
        uint256 timestamp;      
    }

    struct Answer {
        uint256 id;
        uint256 questionId;
        address provider;
        string ipfsHash;
        uint256 timestamp;
    }

    IReputationSystem public reputationSystem;
    IERC20 public immutable USDC;
    
    mapping(uint256 => Question) public questions;
    mapping(uint256 => Answer) public answers;
    mapping(uint256 => mapping(address => bool)) public hasAnswered;
    
    uint256 public questionCounter;
    uint256 public answerCounter;
    uint256 public constant MIN_POOL_DURATION = 1 minutes;
    uint256 public constant MAX_POOL_DURATION = 30 days;
    uint256 public constant PLATFORM_FEE = 200; // 2%
    uint256 public platformUSDCBalance;


    event QuestionCreated(uint256 indexed questionId, address indexed owner, string ipfsHash, uint256 bountyAmount, uint256 poolAmount, uint256 poolEndTime);
    event AnswerSubmitted(uint256 indexed questionId, uint256 indexed answerId, address indexed provider, string ipfsHash);
    event BestAnswerSelected(uint256 indexed questionId, uint256 indexed answerId, address indexed winner, uint256 bountyAmount);
    event PoolDistributed(uint256 indexed questionId, address[] winners, uint256[] amounts);
    event PoolWithdrawn(uint256 indexed questionId, address indexed owner, uint256 withdrawalAmount, uint256 platformFee);
    event BountyWithdrawn(uint256 indexed questionId, address indexed owner, uint256 withdrawalAmount, uint256 platformFee);
    event BountyIncreased(uint256 indexed questionId, uint256 additionalAmount);



    modifier questionExists(uint256 questionId) {
        if (questionId == 0 || questionId > questionCounter) revert QuestionNotFound();
        _;
    }

    modifier answerExists(uint256 answerId) {
        if (answerId == 0 || answerId > answerCounter) revert AnswerNotFound();
        _;
    }

    constructor(address _reputationSystem, address _usdc) Ownable(msg.sender) {
        reputationSystem = IReputationSystem(_reputationSystem);
        USDC = IERC20(_usdc);
    }

    function createQuestion(
        string calldata ipfsHash,
        uint256 bountyAmount,      // USDC amount chosen by user
        uint256 poolDuration,      // Pool duration in seconds (0 if bounty question)
        bool useAsPool
    ) external {
        if (bountyAmount == 0) revert InsufficientBounty();

        // Transfer USDC from user
        if (!USDC.transferFrom(msg.sender, address(this), bountyAmount)) {
            revert USDCTransferFailed();
        }

        questionCounter++;
        
        uint256 finalBountyAmount = 0;
        uint256 poolAmount = 0;
        uint256 poolEndTime = 0;

        if (useAsPool) {
            if (poolDuration < MIN_POOL_DURATION || poolDuration > MAX_POOL_DURATION) {
                revert InvalidPoolDuration();
            }
            poolAmount = bountyAmount;
            poolEndTime = block.timestamp + poolDuration;
        } else {
            finalBountyAmount = bountyAmount;
        }

        questions[questionCounter] = Question({
            id: questionCounter,
            owner: msg.sender,
            ipfsHash: ipfsHash,
            bountyAmount: finalBountyAmount,
            poolAmount: poolAmount,
            poolEndTime: poolEndTime,
            selectedAnswerId: 0,
            answerIds: new uint256[](0),
            poolDistributed: false,
            isActive: true,
            timestamp: block.timestamp
        });

        // Give reputation for asking question
        reputationSystem.updateReputation(msg.sender, 1);

        emit QuestionCreated(questionCounter, msg.sender, ipfsHash, finalBountyAmount, poolAmount, poolEndTime);
    }

    function submitAnswer(
        uint256 questionId,
        string calldata ipfsHash
    ) external questionExists(questionId) {
        if (!reputationSystem.canAnswer(msg.sender)) revert CannotAnswer();
        if (hasAnswered[questionId][msg.sender]) revert AlreadyAnswered();

        Question storage question = questions[questionId];
        if (!question.isActive) revert QuestionNotFound();
        
        // Check if pool has expired
        if (question.poolAmount > 0 && block.timestamp >= question.poolEndTime) {
            revert PoolExpired();
        }

        answerCounter++;
        hasAnswered[questionId][msg.sender] = true;

        answers[answerCounter] = Answer({
            id: answerCounter,
            questionId: questionId,
            provider: msg.sender,
            ipfsHash: ipfsHash,
            timestamp: block.timestamp
        });

        question.answerIds.push(answerCounter);

        // Give reputation for answering
        reputationSystem.updateReputation(msg.sender, 1);

        emit AnswerSubmitted(questionId, answerCounter, msg.sender, ipfsHash);
    }

    function selectBestAnswer(uint256 questionId, uint256 answerId) 
        external 
        questionExists(questionId) 
        answerExists(answerId) 
    {
        Question storage question = questions[questionId];
        if (question.owner != msg.sender) revert NotQuestionOwner();
        if (question.selectedAnswerId != 0) revert BestAnswerAlreadySelected();
        if (question.bountyAmount == 0) revert InsufficientBounty();
        if (question.selectedAnswerId == type(uint256).max) revert BountyAlreadyDistributed();

        Answer memory answer = answers[answerId];
        if (answer.questionId != questionId) revert AnswerNotFound();

        question.selectedAnswerId = answerId;

        // Calculate platform fee
        uint256 bountyAmount = question.bountyAmount;
        uint256 fee = (bountyAmount * PLATFORM_FEE) / 10000;
        uint256 reward = bountyAmount - fee;

        platformUSDCBalance += fee;

        // Give reputation bonus for best answer
        reputationSystem.updateReputation(answer.provider, 10);

        if (!USDC.transfer(answer.provider, reward)) {
            revert USDCTransferFailed();
        }

        // Mark question as inactive since best answer is selected
        question.isActive = false;

        emit BestAnswerSelected(questionId, answerId, answer.provider, reward);
    }

    function increaseBounty(uint256 questionId, uint256 additionalAmount) 
        external 
        questionExists(questionId) 
    {
        if (additionalAmount == 0) revert InsufficientBounty();
        
        Question storage question = questions[questionId];
        if (question.selectedAnswerId == type(uint256).max) revert BountyAlreadyDistributed();
        if (question.selectedAnswerId != 0) revert BestAnswerAlreadySelected();
        
        if (!USDC.transferFrom(msg.sender, address(this), additionalAmount)) {
            revert USDCTransferFailed();
        }
        
        question.bountyAmount += additionalAmount;
        
        emit BountyIncreased(questionId, additionalAmount);
    }

    function distributePool(uint256 questionId) external questionExists(questionId) {
        Question storage question = questions[questionId];
        if (question.poolAmount == 0) revert InsufficientBounty();
        if (question.poolEndTime == 0) revert InsufficientBounty(); // Not a pool question
        if (block.timestamp < question.poolEndTime) revert PoolNotExpired();
        if (question.poolDistributed) revert BestAnswerAlreadySelected();
        if (question.answerIds.length == 0) revert NoAnswers();

        question.poolDistributed = true;

        (address[] memory winners, uint256[] memory rewards) = calculatePoolDistribution(questionId);

        uint256 poolAmount = question.poolAmount;
        uint256 fee = (poolAmount * PLATFORM_FEE) / 10000;
        platformUSDCBalance += fee;
        // Don't set poolAmount to 0 - keep it visible for getter functions

        for (uint256 i = 0; i < winners.length; i++) {
            if (rewards[i] > 0 && winners[i] != address(0)) {
                if (!USDC.transfer(winners[i], rewards[i])) {
                    revert USDCTransferFailed();
                }
            }
        }

        // Mark question as inactive since pool is distributed
        question.isActive = false;

        emit PoolDistributed(questionId, winners, rewards);
    }

    function withdrawPool(uint256 questionId) external questionExists(questionId) {
        Question storage question = questions[questionId];
        if (question.owner != msg.sender) revert NotQuestionOwner();
        if (question.poolAmount == 0) revert InsufficientBounty();
        if (question.poolEndTime == 0) revert InsufficientBounty(); // Not a pool question
        if (question.poolDistributed) revert BestAnswerAlreadySelected();
        if (block.timestamp < question.poolEndTime) revert PoolNotExpired();
        
        // Check if there are any answers with positive reputation
        bool hasGoodAnswers = false;
        for (uint256 i = 0; i < question.answerIds.length; i++) {
            (uint256 upvotes, uint256 downvotes) = reputationSystem.getVoteCount(
                questionId, question.answerIds[i], IReputationSystem.ContentType.ANSWER
            );
            if (upvotes > downvotes) {
                hasGoodAnswers = true;
                break;
            }
        }
        
        if (hasGoodAnswers) revert CannotWithdrawWithGoodAnswers();

        // Mark as distributed to prevent double withdrawal
        question.poolDistributed = true;
        
        // Calculate platform fee
        uint256 poolAmount = question.poolAmount;
        uint256 fee = (poolAmount * PLATFORM_FEE) / 10000;
        uint256 withdrawalAmount = poolAmount - fee;
        
        platformUSDCBalance += fee;
        question.poolAmount = 0;

        // Transfer remaining amount back to question creator
        if (!USDC.transfer(msg.sender, withdrawalAmount)) {
            revert USDCTransferFailed();
        }

        // Mark question as inactive since pool is withdrawn
        question.isActive = false;

        emit PoolWithdrawn(questionId, msg.sender, withdrawalAmount, fee);
    }

    function withdrawBounty(uint256 questionId) external questionExists(questionId) {
        Question storage question = questions[questionId];
        if (question.owner != msg.sender) revert NotQuestionOwner();
        if (question.bountyAmount == 0) revert InsufficientBounty();
        if (question.poolAmount > 0) revert InsufficientBounty(); // Not a bounty question
        if (question.selectedAnswerId != 0) revert BountyAlreadyDistributed();
        
        // Check if there are any answers
        if (question.answerIds.length > 0) revert CannotWithdrawBountyWithAnswers();

        // Mark as distributed to prevent double withdrawal
        question.selectedAnswerId = type(uint256).max; // Special marker for withdrawn
        
        // Calculate platform fee
        uint256 bountyAmount = question.bountyAmount;
        uint256 fee = (bountyAmount * PLATFORM_FEE) / 10000;
        uint256 withdrawalAmount = bountyAmount - fee;
        
        platformUSDCBalance += fee;
        question.bountyAmount = 0;

        // Transfer remaining amount back to question creator
        if (!USDC.transfer(msg.sender, withdrawalAmount)) {
            revert USDCTransferFailed();
        }

        // Mark question as inactive since bounty is withdrawn
        question.isActive = false;

        emit BountyWithdrawn(questionId, msg.sender, withdrawalAmount, fee);
    }

    function vote(
        uint256 questionId,
        uint256 answerId,
        IReputationSystem.ContentType contentType,
        bool isUpvote
    ) external {
        address contentOwner;
        
        if (contentType == IReputationSystem.ContentType.QUESTION) {
            if (questionId == 0 || questionId > questionCounter) revert QuestionNotFound();
            contentOwner = questions[questionId].owner;
        } else {
            if (answerId == 0 || answerId > answerCounter) revert AnswerNotFound();
            contentOwner = answers[answerId].provider;
        }

        reputationSystem.vote(questionId, answerId, contentType, isUpvote, contentOwner, msg.sender);
    }

    function calculateIndividualPoolReward(uint256 questionId, uint256 answerId) 
        internal 
        view 
        returns (uint256) 
    {
        Question storage question = questions[questionId];
        uint256 distributionAmount = question.poolAmount - ((question.poolAmount * PLATFORM_FEE) / 10000);
        uint256 answerCount = question.answerIds.length;
        
        if (answerCount == 0) return 0;
        
        // Get this answer's score
        (uint256 upvotes, uint256 downvotes) = reputationSystem.getVoteCount(
            questionId, answerId, IReputationSystem.ContentType.ANSWER
        );
        int256 answerScore = int256(upvotes) - int256(downvotes);
        
        // If negative score, no reward
        if (answerScore <= 0) return 0;
        
        // Calculate total score for all answers
        uint256 totalScore = 0;
        for (uint256 i = 0; i < answerCount; i++) {
            (uint256 up, uint256 down) = reputationSystem.getVoteCount(
                questionId, question.answerIds[i], IReputationSystem.ContentType.ANSWER
            );
            int256 score = int256(up) - int256(down);
            if (score > 0) {
                totalScore += uint256(score);
            }
        }
        
        if (totalScore == 0) return 0;
        
        // Calculate this answer's share
        uint256 share = (distributionAmount * uint256(answerScore)) / totalScore;
        return share;
    }

    function calculatePoolDistribution(uint256 questionId) 
        internal 
        view 
        returns (address[] memory winners, uint256[] memory rewards) 
    {
        Question storage question = questions[questionId];
        uint256 distributionAmount = question.poolAmount - ((question.poolAmount * PLATFORM_FEE) / 10000);
        uint256 answerCount = question.answerIds.length;
        
        if (answerCount == 0) {
            return (new address[](0), new uint256[](0));
        }

        // Create arrays to store all answers with their scores
        address[] memory allProviders = new address[](answerCount);
        int256[] memory allScores = new int256[](answerCount);
        
        // Calculate scores for all answers
        for (uint256 i = 0; i < answerCount; i++) {
            (uint256 upvotes, uint256 downvotes) = reputationSystem.getVoteCount(
                questionId, question.answerIds[i], IReputationSystem.ContentType.ANSWER
            );
            int256 score = int256(upvotes) - int256(downvotes);
            
            allProviders[i] = answers[question.answerIds[i]].provider;
            allScores[i] = score;
        }
        
        // Sort answers by score (bubble sort for simplicity, can be optimized)
        for (uint256 i = 0; i < answerCount - 1; i++) {
            for (uint256 j = 0; j < answerCount - i - 1; j++) {
                if (allScores[j] < allScores[j + 1]) {
                    // Swap scores
                    int256 tempScore = allScores[j];
                    allScores[j] = allScores[j + 1];
                    allScores[j + 1] = tempScore;
                    
                    // Swap providers
                    address tempProvider = allProviders[j];
                    allProviders[j] = allProviders[j + 1];
                    allProviders[j + 1] = tempProvider;
                }
            }
        }
        
        // Determine number of winners (max 3, but can be less if fewer answers)
        uint256 maxWinners = answerCount > 3 ? 3 : answerCount;
        winners = new address[](maxWinners);
        rewards = new uint256[](maxWinners);
        
        // Calculate total score for weighted distribution
        uint256 totalScore = 0;
        for (uint256 i = 0; i < maxWinners; i++) {
            if (allScores[i] > 0) {
                totalScore += uint256(allScores[i]);
            }
        }
        
        // If no positive scores, distribute equally among all answers
        if (totalScore == 0) {
            uint256 equalShare = distributionAmount / maxWinners;
            uint256 remainder = distributionAmount % maxWinners;
            
            for (uint256 i = 0; i < maxWinners; i++) {
                winners[i] = allProviders[i];
                rewards[i] = equalShare + (i < remainder ? 1 : 0);
            }
        } else {
            // Weighted distribution based on scores
            uint256 distributed = 0;
            for (uint256 i = 0; i < maxWinners; i++) {
                if (allScores[i] > 0) {
                    winners[i] = allProviders[i];
                    uint256 share = (distributionAmount * uint256(allScores[i])) / totalScore;
                    rewards[i] = share;
                    distributed += share;
                }
            }
            
            // Handle rounding errors by giving remainder to first winner
            if (distributed < distributionAmount && maxWinners > 0) {
                rewards[0] += (distributionAmount - distributed);
            }
        }
    }

    function withdrawPlatformFees() external onlyOwner {
        uint256 amount = platformUSDCBalance;
        platformUSDCBalance = 0;
        if (!USDC.transfer(owner(), amount)) {
            revert USDCTransferFailed();
        }
    }

    // View functions - Enhanced and consolidated
    function getQuestion(uint256 questionId) external view returns (
        uint256 id,
        address owner,
        string memory ipfsHash,
        uint256 bountyAmount,
        uint256 poolAmount,
        uint256 poolEndTime,
        uint256 selectedAnswerId,
        uint256[] memory answerIds,
        bool isActive,
        bool isPoolQuestion,
        uint256 timestamp
    ) {
        if (questionId == 0 || questionCounter < questionId) revert QuestionNotFound();
        
        Question storage q = questions[questionId];
        
        return (
            questionId,
            q.owner,
            q.ipfsHash,
            q.bountyAmount,
            q.poolAmount,
            q.poolEndTime,
            q.selectedAnswerId,
            q.answerIds,
            q.isActive,
            q.poolAmount > 0,
            q.timestamp
        );
    }

    function getAnswer(uint256 answerId) external view returns (
        uint256 id,
        uint256 questionId,
        address provider,
        string memory ipfsHash,
        uint256 timestamp,
        uint256 upvotes,
        uint256 downvotes,
        uint256 prizeAmount
    ) {
        if (answerId == 0 || answerId > answerCounter) revert AnswerNotFound();
        
        Answer storage a = answers[answerId];
        (uint256 upvoteCount, uint256 downvoteCount) = reputationSystem.getVoteCount(
            a.questionId, answerId, IReputationSystem.ContentType.ANSWER
        );
        
        // Calculate individual answer's reward amount
        uint256 prize = 0;
        
        if (questions[a.questionId].poolAmount > 0) {
            // Pool question - always calculate the prize amount (whether distributed or not)
            prize = calculateIndividualPoolReward(a.questionId, answerId);
        } else {
            // Bounty question - check if this answer was selected
            if (questions[a.questionId].selectedAnswerId == answerId) {
                // This answer was selected as best answer
                // For bounty questions, return the bounty amount that was earned
                prize = questions[a.questionId].bountyAmount;
            }
            // If not selected, prize = 0
        }
        
        return (
            answerId,
            a.questionId,
            a.provider,
            a.ipfsHash,
            a.timestamp,
            upvoteCount,
            downvoteCount,
            prize
        );
    }

    function getQuestionAnswers(uint256 questionId) external view returns (uint256[] memory) {
        if (questionId == 0 || questionId > questionCounter) revert QuestionNotFound();
        return questions[questionId].answerIds;
    }

    function getVoteCount(
        uint256 questionId,
        uint256 answerId,
        IReputationSystem.ContentType contentType
    ) external view returns (uint256 upvotes, uint256 downvotes) {
        return reputationSystem.getVoteCount(questionId, answerId, contentType);
    }

    function isPoolExpired(uint256 questionId) external view returns (bool) {
        if (questionId == 0 || questionId > questionCounter) revert QuestionNotFound();
        return questions[questionId].poolAmount > 0 && block.timestamp >= questions[questionId].poolEndTime;
    }

    function getUSDCBalance() external view returns (uint256) {
        return USDC.balanceOf(address(this));
    }

    function getAllQuestions() external view returns (
        uint256[] memory questionIds,
        string[] memory ipfsHashes,
        address[] memory creators,
        uint256[] memory amounts,
        bool[] memory isPoolQuestions,
        bool[] memory isActiveQuestions,
        uint256[] memory timestamps
    ) {
        uint256 totalQuestions = questionCounter;
        
        questionIds = new uint256[](totalQuestions);
        ipfsHashes = new string[](totalQuestions);
        creators = new address[](totalQuestions);
        amounts = new uint256[](totalQuestions);
        isPoolQuestions = new bool[](totalQuestions);
        isActiveQuestions = new bool[](totalQuestions);
        timestamps = new uint256[](totalQuestions);
        
        for (uint256 i = 1; i <= totalQuestions; i++) {
            Question storage q = questions[i];
            questionIds[i - 1] = i;
            ipfsHashes[i - 1] = q.ipfsHash;
            creators[i - 1] = q.owner;
            
            // Return pool amount if it's a pool question, bounty amount otherwise
            if (q.poolAmount > 0) {
                amounts[i - 1] = q.poolAmount;
                isPoolQuestions[i - 1] = true;
            } else {
                amounts[i - 1] = q.bountyAmount;
                isPoolQuestions[i - 1] = false;
            }
            
            isActiveQuestions[i - 1] = q.isActive;
            timestamps[i - 1] = q.timestamp;
        }
        
        return (questionIds, ipfsHashes, creators, amounts, isPoolQuestions, isActiveQuestions, timestamps);
    }
}