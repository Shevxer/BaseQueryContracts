// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BaseQuery.sol";
import "../src/ReputationSystem.sol";
import "../src/MockUSDC.sol";

contract StackExchangeTest is Test {
    StackExchange public stackExchange;
    ReputationSystem public reputationSystem;
    MockUSDC public usdc;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public dave = address(0x4);
    
    uint256 public constant MIN_ETH_BALANCE = 1000000000000000; // 0.001 ETH
    uint256 public constant USDC_AMOUNT = 1000000; // 1 USDC (6 decimals)
    uint256 public constant POOL_DURATION = 1 hours;
    
    event QuestionCreated(uint256 indexed questionId, address indexed owner, string ipfsHash, uint256 bountyAmount, uint256 poolAmount, uint256 poolEndTime);
    event AnswerSubmitted(uint256 indexed questionId, uint256 indexed answerId, address indexed provider, string ipfsHash);
    event BestAnswerSelected(uint256 indexed questionId, uint256 indexed answerId, address indexed winner, uint256 bountyAmount);
    event PoolDistributed(uint256 indexed questionId, address[] winners, uint256[] amounts);
    event BountyWithdrawn(uint256 indexed questionId, address indexed owner, uint256 withdrawalAmount, uint256 platformFee);

    function setUp() public {
        // Deploy contracts
        reputationSystem = new ReputationSystem();
        usdc = new MockUSDC();
        stackExchange = new StackExchange(address(reputationSystem), address(usdc));
        
        // Set up authorization
        reputationSystem.setAuthorizedCaller(address(stackExchange), true);
        
        // Fund test accounts with ETH and USDC
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.deal(charlie, 1 ether);
        vm.deal(dave, 1 ether);
        
        usdc.mint(alice, 10000000); // 10 USDC
        usdc.mint(bob, 10000000);   // 10 USDC
        usdc.mint(charlie, 10000000); // 10 USDC
        usdc.mint(dave, 10000000);    // 10 USDC
        
        // Approve USDC spending
        vm.prank(alice);
        usdc.approve(address(stackExchange), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(stackExchange), type(uint256).max);
        vm.prank(charlie);
        usdc.approve(address(stackExchange), type(uint256).max);
        vm.prank(dave);
        usdc.approve(address(stackExchange), type(uint256).max);
    }

    function test_CreateBountyQuestion() public {
        vm.prank(alice);
        
        vm.expectEmit(true, true, false, true);
        emit QuestionCreated(1, alice, "QmBountyHash", USDC_AMOUNT, 0, 0);
        
        stackExchange.createQuestion("QmBountyHash", USDC_AMOUNT, 0, false);
        
        (
            uint256 id,
            address owner,
            string memory ipfsHash,
            uint256 bountyAmount,
            uint256 poolAmount,
            uint256 poolEndTime,
            uint256 selectedAnswerId,
            uint256[] memory answerIds,
            bool poolDistributed,
            bool isActive,
            bool isPoolQuestion,
            uint256 timestamp
        ) = stackExchange.getQuestion(1);
        assertEq(owner, alice);
        assertEq(bountyAmount, USDC_AMOUNT);
        assertEq(poolAmount, 0);
        assertTrue(isActive);
        
        // Check reputation increase
        (uint256 score,) = reputationSystem.getUserReputation(alice);
        assertEq(score, 1);
    }

    function test_CreatePoolQuestion() public {
        vm.prank(alice);
        
        vm.expectEmit(true, true, false, true);
        emit QuestionCreated(1, alice, "QmPoolHash", 0, USDC_AMOUNT, block.timestamp + POOL_DURATION);
        
        stackExchange.createQuestion("QmPoolHash", USDC_AMOUNT, POOL_DURATION, true);
        
        (
            uint256 id,
            address owner,
            string memory ipfsHash,
            uint256 bountyAmount,
            uint256 poolAmount,
            uint256 poolEndTime,
            uint256 selectedAnswerId,
            uint256[] memory answerIds,
            bool poolDistributed,
            bool isActive,
            bool isPoolQuestion,
            uint256 timestamp
        ) = stackExchange.getQuestion(1);
        assertEq(owner, alice);
        assertEq(bountyAmount, 0);
        assertEq(poolAmount, USDC_AMOUNT);
        assertEq(poolEndTime, block.timestamp + POOL_DURATION);
        assertTrue(isActive);
    }

    function test_SubmitAnswer() public {
        // Create question first
        vm.prank(alice);
        stackExchange.createQuestion("QmQuestionHash", USDC_AMOUNT, 0, false);
        
        // Submit answer
        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit AnswerSubmitted(1, 1, bob, "QmAnswerHash");
        
        stackExchange.submitAnswer(1, "QmAnswerHash");
        
        (
            uint256 answerId1,
            uint256 questionId1,
            address provider1,
            string memory ipfsHash1,
            uint256 timestamp1,
            uint256 upvotes1,
            uint256 downvotes1,
            uint256 prizeAmount1
        ) = stackExchange.getAnswer(1);
        assertEq(provider1, bob);
        assertEq(questionId1, 1);
        assertEq(ipfsHash1, "QmAnswerHash");
        
        // Check reputation increase
        (uint256 score,) = reputationSystem.getUserReputation(bob);
        assertEq(score, 1);
        
        // Check that bob has answered
        assertTrue(stackExchange.hasAnswered(1, bob));
    }

    function test_CannotAnswerTwice() public {
        // Create question
        vm.prank(alice);
        stackExchange.createQuestion("QmQuestionHash", USDC_AMOUNT, 0, false);
        
        // Submit first answer
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmAnswer1Hash");
        
        // Try to submit second answer
        vm.prank(bob);
        vm.expectRevert(StackExchange.AlreadyAnswered.selector);
        stackExchange.submitAnswer(1, "QmAnswer2Hash");
    }

    function test_SelectBestAnswer() public {
        // Create question
        vm.prank(alice);
        stackExchange.createQuestion("QmQuestionHash", USDC_AMOUNT, 0, false);
        
        // Submit answer
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmAnswerHash");
        
        // Select best answer
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit BestAnswerSelected(1, 1, bob, USDC_AMOUNT - (USDC_AMOUNT * 200 / 10000));
        
        stackExchange.selectBestAnswer(1, 1);
        
        // Check bounty is transferred
        uint256 bobBalance = usdc.balanceOf(bob);
        assertEq(bobBalance, 10000000 + (USDC_AMOUNT - (USDC_AMOUNT * 200 / 10000)));
        
        // Check reputation bonus
        (uint256 score,) = reputationSystem.getUserReputation(bob);
        assertEq(score, 11); // 1 for answering + 10 for best answer
    }

    function test_DistributePool() public {
        // Create pool question
        vm.prank(alice);
        stackExchange.createQuestion("QmPoolHash", USDC_AMOUNT, POOL_DURATION, true);
        
        // Submit answers
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmBobAnswerHash");
        
        vm.prank(charlie);
        stackExchange.submitAnswer(1, "QmCharlieAnswerHash");
        
        // Vote on answers - both get 1 upvote, so equal scores
        vm.prank(dave);
        stackExchange.vote(1, 1, IReputationSystem.ContentType.ANSWER, true);
        
        vm.prank(alice);
        stackExchange.vote(1, 2, IReputationSystem.ContentType.ANSWER, true);
        
        // Fast forward time
        vm.warp(block.timestamp + POOL_DURATION + 1);
        
        // Distribute pool - now uses weighted distribution based on scores
        // Both have score 1, so they should get equal shares
        stackExchange.distributePool(1);
        
        // Check pool is distributed
        (
            uint256 id,
            address owner,
            string memory ipfsHash,
            uint256 bountyAmount,
            uint256 poolAmount,
            uint256 poolEndTime,
            uint256 selectedAnswerId,
            uint256[] memory answerIds,
            bool poolDistributed,
            bool isActive,
            bool isPoolQuestion,
            uint256 timestamp
        ) = stackExchange.getQuestion(1);
        assertTrue(poolDistributed);
        assertEq(poolAmount, 0);
        
        // Check that both got rewards (exact amounts depend on new algorithm)
        uint256 bobBalance = usdc.balanceOf(bob);
        uint256 charlieBalance = usdc.balanceOf(charlie);
        
        // Both should have received rewards
        assertGt(bobBalance, 10000000); // More than initial 10 USDC
        assertGt(charlieBalance, 10000000);
        
        // Since both have same score (1), they should get similar amounts
        uint256 bobReward = bobBalance - 10000000;
        uint256 charlieReward = charlieBalance - 10000000;
        assertApproxEqRel(bobReward, charlieReward, 0.1e18); // Within 10%
    }

    function test_VotingSystem() public {
        // Create question
        vm.prank(alice);
        stackExchange.createQuestion("QmQuestionHash", USDC_AMOUNT, 0, false);
        
        // Submit answer
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmAnswerHash");
        
        // Vote on answer
        vm.prank(charlie);
        stackExchange.vote(1, 1, IReputationSystem.ContentType.ANSWER, true);
        
        // Check vote count
        (uint256 upvotes, uint256 downvotes) = stackExchange.getVoteCount(1, 1, IReputationSystem.ContentType.ANSWER);
        assertEq(upvotes, 1);
        assertEq(downvotes, 0);
        
        // Check reputation change
        (uint256 score,) = reputationSystem.getUserReputation(bob);
        assertEq(score, 3); // 1 for answering + 2 for upvote
    }

    function test_CannotVoteOnOwnContent() public {
        // Create question
        vm.prank(alice);
        stackExchange.createQuestion("QmQuestionHash", USDC_AMOUNT, 0, false);
        
        // Try to vote on own question
        vm.prank(alice);
        vm.expectRevert();
        stackExchange.vote(1, 0, IReputationSystem.ContentType.QUESTION, true);
    }

    function test_IncreaseBounty() public {
        // Create question
        vm.prank(alice);
        stackExchange.createQuestion("QmQuestionHash", USDC_AMOUNT, 0, false);
        
        // Increase bounty
        vm.prank(alice);
        stackExchange.increaseBounty(1, USDC_AMOUNT);
        
        (
            uint256 id,
            address owner,
            string memory ipfsHash,
            uint256 bountyAmount,
            uint256 poolAmount,
            uint256 poolEndTime,
            uint256 selectedAnswerId,
            uint256[] memory answerIds,
            bool poolDistributed,
            bool isActive,
            bool isPoolQuestion,
            uint256 timestamp
        ) = stackExchange.getQuestion(1);
        assertEq(bountyAmount, USDC_AMOUNT * 2);
    }

    function test_WithdrawPlatformFees() public {
        // Create and complete a question to generate fees
        vm.prank(alice);
        stackExchange.createQuestion("QmQuestionHash", USDC_AMOUNT, 0, false);
        
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmAnswerHash");
        
        vm.prank(alice);
        stackExchange.selectBestAnswer(1, 1);
        
        // Check platform fees
        uint256 platformBalance = stackExchange.getUSDCBalance();
        assertGt(platformBalance, 0);
        
        // Withdraw fees
        vm.prank(address(stackExchange.owner()));
        stackExchange.withdrawPlatformFees();
        
        // Check fees are withdrawn
        platformBalance = stackExchange.getUSDCBalance();
        assertEq(platformBalance, 0);
    }

    function test_ReputationSystemIntegration() public {
        // Test that reputation system is properly integrated
        assertTrue(reputationSystem.canAnswer(alice));
        assertTrue(reputationSystem.canVote(alice));
        
        // Test reputation update
        reputationSystem.updateReputation(alice, 10);
        (uint256 score,) = reputationSystem.getUserReputation(alice);
        assertEq(score, 10);
    }

    function test_ErrorConditions() public {
        // Test insufficient bounty
        vm.prank(alice);
        vm.expectRevert(StackExchange.InsufficientBounty.selector);
        stackExchange.createQuestion("QmHash", 0, 0, false);
        
        // Test question not found
        vm.prank(bob);
        vm.expectRevert(StackExchange.QuestionNotFound.selector);
        stackExchange.submitAnswer(999, "QmHash");
        
        // Test not question owner
        vm.prank(alice);
        stackExchange.createQuestion("QmHash", USDC_AMOUNT, 0, false);
        
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmHash");
        
        vm.prank(charlie);
        vm.expectRevert(StackExchange.NotQuestionOwner.selector);
        stackExchange.selectBestAnswer(1, 1);
    }

    function test_PoolQuestionEdgeCases() public {
        // Test pool duration constraints
        vm.prank(alice);
        vm.expectRevert(StackExchange.InvalidPoolDuration.selector);
        stackExchange.createQuestion("QmHash", USDC_AMOUNT, 30 minutes, true); // Too short
        
        vm.prank(alice);
        vm.expectRevert(StackExchange.InvalidPoolDuration.selector);
        stackExchange.createQuestion("QmHash", USDC_AMOUNT, 31 days, true); // Too long
        
        // Test pool expiration
        vm.prank(alice);
        stackExchange.createQuestion("QmPoolHash", USDC_AMOUNT, POOL_DURATION, true);
        
        // Try to answer after pool expires
        vm.warp(block.timestamp + POOL_DURATION + 1);
        vm.prank(bob);
        vm.expectRevert(StackExchange.PoolExpired.selector);
        stackExchange.submitAnswer(1, "QmAnswerHash");
    }

    function test_QuestionLifecycle() public {
        // Test question creation and status
        vm.prank(alice);
        stackExchange.createQuestion("QmHash", USDC_AMOUNT, 0, false);
        
        (
            uint256 id,
            address owner,
            string memory ipfsHash,
            uint256 bountyAmount,
            uint256 poolAmount,
            uint256 poolEndTime,
            uint256 selectedAnswerId,
            uint256[] memory answerIds,
            bool poolDistributed,
            bool isActive,
            bool isPoolQuestion,
            uint256 timestamp
        ) = stackExchange.getQuestion(1);
        assertTrue(isActive);
        assertEq(owner, alice);
        assertEq(bountyAmount, USDC_AMOUNT);
        
        // Test answer submission
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmAnswerHash");
        
        // Verify answer details
        (
            uint256 answerId,
            uint256 questionId,
            address provider,
            string memory answerIpfsHash,
            uint256 answerTimestamp,
            uint256 upvotes,
            uint256 downvotes,
            uint256 prizeAmount
        ) = stackExchange.getAnswer(1);
        assertEq(provider, bob);
        assertEq(questionId, 1);
        assertEq(answerIpfsHash, "QmAnswerHash");
        
        // Test question details using the enhanced getQuestion function
        (
            uint256 qId,
            address questionOwner,
            string memory qIpfsHash,
            uint256 qBountyAmount,
            uint256 qPoolAmount,
            uint256 qPoolEndTime,
            uint256 qSelectedAnswerId,
            uint256[] memory qAnswerIds,
            bool qPoolDistributed,
            bool qIsActive,
            bool qIsPoolQuestion,
            uint256 qTimestamp
        ) = stackExchange.getQuestion(1);
        
        assertEq(questionOwner, alice);
        assertEq(qBountyAmount, USDC_AMOUNT);
        assertEq(qPoolAmount, 0);
        assertEq(qPoolEndTime, 0);
        assertEq(qAnswerIds.length, 1);
        assertFalse(qPoolDistributed);
        assertFalse(qIsPoolQuestion);
        assertGt(qTimestamp, 0);
    }

    function test_ReputationIntegration() public {
        // Test reputation updates through actions
        (uint256 aliceInitialRep, uint256 aliceInitialVotes) = reputationSystem.getUserReputation(alice);
        
        // Create question should give +1 reputation
        vm.prank(alice);
        stackExchange.createQuestion("QmHash", USDC_AMOUNT, 0, false);
        
        (uint256 aliceRepAfterQuestion, uint256 aliceVotesAfterQuestion) = reputationSystem.getUserReputation(alice);
        assertEq(aliceRepAfterQuestion, aliceInitialRep + 1);
        
        // Submit answer should give +1 reputation
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmAnswerHash");
        
        (uint256 bobRep, uint256 bobVotes) = reputationSystem.getUserReputation(bob);
        assertEq(bobRep, 1); // 1 for answering
        
        // Select best answer should give +10 reputation
        vm.prank(alice);
        stackExchange.selectBestAnswer(1, 1);
        
        (bobRep, bobVotes) = reputationSystem.getUserReputation(bob);
        assertEq(bobRep, 11); // 1 for answering + 10 for best answer
    }

    // ========== BOUNTY WITHDRAWAL TESTS ==========

    function test_WithdrawBountySuccess() public {
        // Create a bounty question
        vm.prank(alice);
        stackExchange.createQuestion("QmBountyHash", USDC_AMOUNT, 0, false);
        
        uint256 aliceInitialBalance = usdc.balanceOf(alice);
        
        // Withdraw bounty before any answers
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit BountyWithdrawn(1, alice, USDC_AMOUNT - (USDC_AMOUNT * 200 / 10000), USDC_AMOUNT * 200 / 10000);
        
        stackExchange.withdrawBounty(1);
        
        // Check balances
        uint256 aliceFinalBalance = usdc.balanceOf(alice);
        uint256 expectedWithdrawal = USDC_AMOUNT - (USDC_AMOUNT * 200 / 10000); // 2% platform fee
        assertEq(aliceFinalBalance, aliceInitialBalance + expectedWithdrawal);
        
        // Check question state
        (
            uint256 id,
            address owner,
            string memory ipfsHash,
            uint256 bountyAmount,
            uint256 poolAmount,
            uint256 poolEndTime,
            uint256 selectedAnswerId,
            uint256[] memory answerIds,
            bool poolDistributed,
            bool isActive,
            bool isPoolQuestion,
            uint256 timestamp
        ) = stackExchange.getQuestion(1);
        assertEq(bountyAmount, 0);
        assertEq(selectedAnswerId, type(uint256).max); // Withdrawn marker
        
        // Check platform fee balance
        assertEq(stackExchange.getUSDCBalance(), USDC_AMOUNT * 200 / 10000);
    }

    function test_WithdrawBountyWithAnswers() public {
        // Create a bounty question
        vm.prank(alice);
        stackExchange.createQuestion("QmBountyHash", USDC_AMOUNT, 0, false);
        
        // Submit an answer
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmAnswerHash");
        
        // Try to withdraw bounty - should fail
        vm.prank(alice);
        vm.expectRevert(StackExchange.CannotWithdrawBountyWithAnswers.selector);
        stackExchange.withdrawBounty(1);
        
        // Check question state remains unchanged
        (
            uint256 id,
            address owner,
            string memory ipfsHash,
            uint256 bountyAmount,
            uint256 poolAmount,
            uint256 poolEndTime,
            uint256 selectedAnswerId,
            uint256[] memory answerIds,
            bool poolDistributed,
            bool isActive,
            bool isPoolQuestion,
            uint256 timestamp
        ) = stackExchange.getQuestion(1);
        assertEq(bountyAmount, USDC_AMOUNT);
        assertEq(selectedAnswerId, 0);
    }

    function test_WithdrawBountyNotOwner() public {
        // Create a bounty question
        vm.prank(alice);
        stackExchange.createQuestion("QmBountyHash", USDC_AMOUNT, 0, false);
        
        // Try to withdraw as non-owner
        vm.prank(bob);
        vm.expectRevert(StackExchange.NotQuestionOwner.selector);
        stackExchange.withdrawBounty(1);
    }

    function test_WithdrawBountyAlreadyDistributed() public {
        // Create a bounty question
        vm.prank(alice);
        stackExchange.createQuestion("QmBountyHash", USDC_AMOUNT, 0, false);
        
        // Submit an answer
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmAnswerHash");
        
        // Select best answer
        vm.prank(alice);
        stackExchange.selectBestAnswer(1, 1);
        
        // Try to withdraw bounty - should fail (bounty is already 0)
        vm.prank(alice);
        vm.expectRevert(StackExchange.InsufficientBounty.selector);
        stackExchange.withdrawBounty(1);
    }

    function test_WithdrawBountyPoolQuestion() public {
        // Create a pool question
        vm.prank(alice);
        stackExchange.createQuestion("QmPoolHash", USDC_AMOUNT, POOL_DURATION, true);
        
        // Try to withdraw bounty from pool question - should fail
        vm.prank(alice);
        vm.expectRevert(StackExchange.InsufficientBounty.selector);
        stackExchange.withdrawBounty(1);
    }

    function test_WithdrawBountyNoBounty() public {
        // Create a bounty question
        vm.prank(alice);
        stackExchange.createQuestion("QmBountyHash", USDC_AMOUNT, 0, false);
        
        // Withdraw bounty
        vm.prank(alice);
        stackExchange.withdrawBounty(1);
        
        // Try to withdraw again - should fail
        vm.prank(alice);
        vm.expectRevert(StackExchange.InsufficientBounty.selector);
        stackExchange.withdrawBounty(1);
    }

    function test_WithdrawBountyAfterWithdrawal() public {
        // Create a bounty question
        vm.prank(alice);
        stackExchange.createQuestion("QmBountyHash", USDC_AMOUNT, 0, false);
        
        // Withdraw bounty
        vm.prank(alice);
        stackExchange.withdrawBounty(1);
        
        // Try to increase bounty - should fail
        vm.prank(alice);
        vm.expectRevert(StackExchange.BountyAlreadyDistributed.selector);
        stackExchange.increaseBounty(1, USDC_AMOUNT);
    }

    function test_WithdrawBountyMultipleQuestions() public {
        // Create multiple bounty questions
        vm.prank(alice);
        stackExchange.createQuestion("QmBountyHash1", USDC_AMOUNT, 0, false);
        
        vm.prank(bob);
        stackExchange.createQuestion("QmBountyHash2", USDC_AMOUNT * 2, 0, false);
        
        uint256 aliceInitialBalance = usdc.balanceOf(alice);
        uint256 bobInitialBalance = usdc.balanceOf(bob);
        
        // Withdraw both bounties
        vm.prank(alice);
        stackExchange.withdrawBounty(1);
        
        vm.prank(bob);
        stackExchange.withdrawBounty(2);
        
        // Check balances
        uint256 aliceFinalBalance = usdc.balanceOf(alice);
        uint256 bobFinalBalance = usdc.balanceOf(bob);
        
        uint256 aliceExpectedWithdrawal = USDC_AMOUNT - (USDC_AMOUNT * 200 / 10000);
        uint256 bobExpectedWithdrawal = (USDC_AMOUNT * 2) - ((USDC_AMOUNT * 2) * 200 / 10000);
        
        assertEq(aliceFinalBalance, aliceInitialBalance + aliceExpectedWithdrawal);
        assertEq(bobFinalBalance, bobInitialBalance + bobExpectedWithdrawal);
        
        // Check platform fee balance
        uint256 totalFees = (USDC_AMOUNT * 200 / 10000) + ((USDC_AMOUNT * 2) * 200 / 10000);
        assertEq(stackExchange.getUSDCBalance(), totalFees);
    }
}
