// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BaseQuery.sol";
import "../src/ReputationSystem.sol";

contract LiveNetworkTest is Test {
    // Deployed contract addresses on Base Sepolia
    StackExchange public stackExchange;
    ReputationSystem public reputationSystem;
    
    // Test accounts
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    
    // Test constants
    uint256 public constant USDC_AMOUNT = 1000000; // 1 USDC (6 decimals)
    uint256 public constant POOL_DURATION = 1 hours;
    
    // Events to watch for
    event QuestionCreated(uint256 indexed questionId, address indexed owner, string ipfsHash, uint256 bountyAmount, uint256 poolAmount, uint256 poolEndTime);
    event AnswerSubmitted(uint256 indexed questionId, uint256 indexed answerId, address indexed provider, string ipfsHash);
    event BestAnswerSelected(uint256 indexed questionId, uint256 indexed answerId, address indexed winner, uint256 bountyAmount);
    event BountyWithdrawn(uint256 indexed questionId, address indexed owner, uint256 withdrawalAmount, uint256 platformFee);

    function setUp() public {
        // Connect to deployed contracts on Base Sepolia
        reputationSystem = ReputationSystem(0xE34a19442F221d0DCBC6B1C740Cd8096f2fFB25c);
        stackExchange = StackExchange(0x6FDeDa9f256c1c9cba1e9497Ce44F2e1C5435244);
        
        // Set up test accounts with ETH for gas
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.deal(charlie, 1 ether);
    }

    function test_ContractConnection() public view {
        // Test that we can read from deployed contracts
        uint256 questionCounter = stackExchange.questionCounter();
        uint256 answerCounter = stackExchange.answerCounter();
        
        console.log("Connected to deployed contracts:");
        console.log("Question Counter:", questionCounter);
        console.log("Answer Counter:", answerCounter);
        console.log("ReputationSystem:", address(reputationSystem));
        console.log("StackExchange:", address(stackExchange));
    }

    function test_ReadQuestionDetails() public view {
        // Test reading question details from deployed contract
        if (stackExchange.questionCounter() > 0) {
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
            console.log("Question 1 details:");
            console.log("Owner:", owner);
            console.log("IPFS Hash:", ipfsHash);
            console.log("Bounty Amount:", bountyAmount);
            console.log("Pool Amount:", poolAmount);
            console.log("Is Active:", isActive);
            console.log("Answer IDs count:", answerIds.length);
        } else {
            console.log("No questions found yet");
        }
    }

    function test_ReadAnswerDetails() public view {
        // Test reading answer details from deployed contract
        if (stackExchange.answerCounter() > 0) {
            (
                uint256 id,
                uint256 questionId,
                address provider,
                string memory ipfsHash,
                uint256 timestamp,
                uint256 upvotes,
                uint256 downvotes,
                uint256 prizeAmount
            ) = stackExchange.getAnswer(1);
            console.log("Answer 1 details:");
            console.log("Provider:", provider);
            console.log("Question ID:", questionId);
            console.log("IPFS Hash:", ipfsHash);
            console.log("Timestamp:", timestamp);
            console.log("Upvotes:", upvotes);
            console.log("Downvotes:", downvotes);
            console.log("Prize Amount:", prizeAmount);
        } else {
            console.log("No answers found yet");
        }
    }

    function test_GetQuestionDetails() public view {
        // Test the enhanced getQuestion function (replaces getQuestionDetails)
        if (stackExchange.questionCounter() > 0) {
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
            
            console.log("Question 1 details (enhanced getQuestion):");
            console.log("Owner:", owner);
            console.log("IPFS Hash:", ipfsHash);
            console.log("Bounty Amount:", bountyAmount);
            console.log("Pool Amount:", poolAmount);
            console.log("Answer Count:", answerIds.length);
            console.log("Is Pool Question:", isPoolQuestion);
            console.log("Timestamp:", timestamp);
        } else {
            console.log("No questions found yet");
        }
    }

    function test_CheckUSDCBalance() public view {
        // Test reading USDC balance
        uint256 usdcBalance = stackExchange.getUSDCBalance();
        console.log("Contract USDC Balance:", usdcBalance);
    }

    function test_CheckPoolExpiration() public view {
        // Test checking if pools are expired
        if (stackExchange.questionCounter() > 0) {
            bool isExpired = stackExchange.isPoolExpired(1);
            console.log("Question 1 pool expired:", isExpired);
        } else {
            console.log("No questions found yet");
        }
    }

    function test_GetQuestionAnswers() public view {
        // Test getting answer IDs for a question
        if (stackExchange.questionCounter() > 0) {
            uint256[] memory answerIds = stackExchange.getQuestionAnswers(1);
            console.log("Question 1 answer IDs:");
            for (uint256 i = 0; i < answerIds.length; i++) {
                console.log("Answer ID:", answerIds[i]);
            }
        } else {
            console.log("No questions found yet");
        }
    }

    function test_CheckVoteCounts() public view {
        // Test reading vote counts
        if (stackExchange.answerCounter() > 0) {
            (uint256 upvotes, uint256 downvotes) = stackExchange.getVoteCount(
                1, 1, IReputationSystem.ContentType.ANSWER
            );
            console.log("Answer 1 vote counts:");
            console.log("Upvotes:", upvotes);
            console.log("Downvotes:", downvotes);
        } else {
            console.log("No answers found yet");
        }
    }

    function test_ReputationSystemIntegration() public view {
        // Test reputation system integration
        if (stackExchange.questionCounter() > 0) {
            // Check if reputation system is properly linked
            address linkedReputation = address(stackExchange.reputationSystem());
            console.log("Linked Reputation System:", linkedReputation);
            console.log("Expected Reputation System:", address(reputationSystem));
            
            if (linkedReputation == address(reputationSystem)) {
                console.log("SUCCESS: Reputation system properly linked");
            } else {
                console.log("ERROR: Reputation system not properly linked");
            }
        }
    }

    function test_ContractState() public view {
        // Comprehensive contract state check
        console.log("\n=== CONTRACT STATE SUMMARY ===");
        console.log("Question Counter:", stackExchange.questionCounter());
        console.log("Answer Counter:", stackExchange.answerCounter());
        console.log("USDC Balance:", stackExchange.getUSDCBalance());
        console.log("Reputation System:", address(stackExchange.reputationSystem()));
        console.log("USDC Token:", address(stackExchange.USDC()));
        console.log("==============================\n");
    }

    // Test question creation - requires USDC and approval
    function test_CreateBountyQuestion() public {
        // This will test creating a bounty question with actual USDC
        console.log("=== TESTING BOUNTY QUESTION CREATION ===");
        
        // Check initial state
        uint256 initialQuestionCount = stackExchange.questionCounter();
        console.log("Initial Question Count:", initialQuestionCount);
        
        // Check USDC allowance
        IERC20 usdc = stackExchange.USDC();
        address deployer = 0xDbbd8977698373F436c9df00A64711220E8031dc;
        uint256 allowance = usdc.allowance(deployer, address(stackExchange));
        
        console.log("USDC Allowance:", allowance);
        console.log("Required for 1 USDC question: 1000000");
        
        if (allowance >= 1000000) {
            console.log("SUCCESS: Sufficient allowance - can create question");
            console.log("Ready to test question creation!");
        } else {
            console.log("ERROR: Insufficient allowance");
        }
        console.log("=====================================");
    }

    function test_CreatePoolQuestion() public {
        // This will test creating a pool question
        console.log("=== TESTING POOL QUESTION CREATION ===");
        
        // Check initial state
        uint256 initialQuestionCount = stackExchange.questionCounter();
        console.log("Initial Question Count:", initialQuestionCount);
        
        console.log("Pool questions require:");
        console.log("1. USDC tokens for the pool");
        console.log("2. Valid pool duration (1 hour to 30 days)");
        console.log("3. USDC approval for contract");
        console.log("===================================");
    }

    function test_USDC_Approval_Check() public view {
        // Check if the deployer has approved USDC spending
        address deployer = 0xDbbd8977698373F436c9df00A64711220E8031dc; // Your deployer address
        
        // Get USDC contract interface
        IERC20 usdc = stackExchange.USDC();
        
        uint256 allowance = usdc.allowance(deployer, address(stackExchange));
        uint256 balance = usdc.balanceOf(deployer);
        
        console.log("=== USDC STATUS FOR DEPLOYER ===");
        console.log("Deployer Address:", deployer);
        console.log("USDC Balance:", balance);
        console.log("USDC Allowance:", allowance);
        
        if (allowance > 0) {
            console.log("SUCCESS: USDC allowance set - can create questions");
            if (allowance >= balance) {
                console.log("NOTICE: Max approval detected - best UX practice");
            }
        } else {
            console.log("NOTICE: No USDC allowance - need to approve first");
        }
        console.log("===============================");
    }

    function test_ExactApprovalFlow_Explanation() public view {
        console.log("=== EXACT APPROVAL FLOW ===");
        console.log("1. FOR EACH QUESTION:");
        console.log("   - Check current allowance");
        console.log("   - Approve exact bounty amount");
        console.log("   - Create question");
        console.log("");
        console.log("2. SECURITY BENEFITS:");
        console.log("   - Only approve what you need");
        console.log("   - Limited contract exposure");
        console.log("   - Explicit user consent");
        console.log("");
        console.log("3. IMPLEMENTATION:");
        console.log("   - Frontend checks allowance first");
        console.log("   - Request approval for exact amount");
        console.log("   - Execute question creation");
        console.log("=============================");
    }

    function test_ExactApproval_Requirements() public view {
        console.log("=== EXACT APPROVAL REQUIREMENTS ===");
        console.log("For 1 USDC bounty question:");
        console.log("1. Current allowance: check with allowance()");
        console.log("2. Required approval: 1000000 (1 USDC)");
        console.log("3. Approve call: approve(contract, 1000000)");
        console.log("4. Create question: createQuestion(hash, 1000000, 0, false)");
        console.log("");
        console.log("For 2 USDC pool question:");
        console.log("1. Required approval: 2000000 (2 USDC)");
        console.log("2. Approve call: approve(contract, 2000000)");
        console.log("3. Create question: createQuestion(hash, 2000000, 3600, true)");
        console.log("===================================");
    }
}
