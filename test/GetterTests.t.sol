// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BaseQuery.sol";
import "../src/ReputationSystem.sol";
import "../src/MockUSDC.sol";

contract GetterTests is Test {
    BaseQuery public baseQuery;
    ReputationSystem public reputationSystem;
    MockUSDC public usdc;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public dave = address(0x4);
    
    uint256 public constant USDC_AMOUNT = 1000000; // 1 USDC (6 decimals)
    uint256 public constant POOL_DURATION = 1 hours;
    
    function setUp() public {
        // Deploy contracts
        reputationSystem = new ReputationSystem();
        usdc = new MockUSDC();
        baseQuery = new BaseQuery(address(reputationSystem), address(usdc));
        
        // Set up authorization
        reputationSystem.setAuthorizedCaller(address(baseQuery), true);
        
        // Fund test accounts with ETH and USDC
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        vm.deal(charlie, 1 ether);
        vm.deal(dave, 1 ether);
        
        // Mint USDC to test accounts
        usdc.mint(alice, 10000000); // 10 USDC
        usdc.mint(bob, 10000000);   // 10 USDC
        usdc.mint(charlie, 10000000); // 10 USDC
        usdc.mint(dave, 10000000);    // 10 USDC
        
        // Approve USDC spending
        vm.prank(alice);
        usdc.approve(address(baseQuery), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(baseQuery), type(uint256).max);
        vm.prank(charlie);
        usdc.approve(address(baseQuery), type(uint256).max);
        vm.prank(dave);
        usdc.approve(address(baseQuery), type(uint256).max);
    }

    // ========== GETQUESTION TESTS ==========
    
    function test_GetQuestion_BountyQuestion() public {
        // Create a bounty question
        vm.prank(alice);
        baseQuery.createQuestion("QmBountyHash", USDC_AMOUNT, 0, false);
        
        // Test getQuestion
        (
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
        ) = baseQuery.getQuestion(1);
        
        // Verify all fields
        assertEq(id, 1);
        assertEq(owner, alice);
        assertEq(ipfsHash, "QmBountyHash");
        assertEq(bountyAmount, USDC_AMOUNT);
        assertEq(poolAmount, 0);
        assertEq(poolEndTime, 0);
        assertEq(selectedAnswerId, 0);
        assertEq(answerIds.length, 0);
        assertTrue(isActive);
        assertFalse(isPoolQuestion);
        assertGt(timestamp, 0);
        
        console.log("getQuestion bounty question test passed");
    }
    
    function test_GetQuestion_PoolQuestion() public {
        // Create a pool question
        vm.prank(alice);
        baseQuery.createQuestion("QmPoolHash", USDC_AMOUNT, POOL_DURATION, true);
        
        // Test getQuestion
        (
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
        ) = baseQuery.getQuestion(1);
        
        // Verify all fields
        assertEq(id, 1);
        assertEq(owner, alice);
        assertEq(ipfsHash, "QmPoolHash");
        assertEq(bountyAmount, 0);
        assertEq(poolAmount, USDC_AMOUNT);
        assertEq(poolEndTime, block.timestamp + POOL_DURATION);
        assertEq(selectedAnswerId, 0);
        assertEq(answerIds.length, 0);
        assertTrue(isActive);
        assertTrue(isPoolQuestion);
        assertGt(timestamp, 0);
        
        console.log("getQuestion pool question test passed");
    }
    
    function test_GetQuestion_WithAnswers() public {
        // Create a question
        vm.prank(alice);
        baseQuery.createQuestion("QmQuestionHash", USDC_AMOUNT, 0, false);
        
        // Submit answers
        vm.prank(bob);
        baseQuery.submitAnswer(1, "QmBobAnswer");
        
        vm.prank(charlie);
        baseQuery.submitAnswer(1, "QmCharlieAnswer");
        
        // Test getQuestion
        (
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
        ) = baseQuery.getQuestion(1);
        
        // Verify answer-related fields
        assertEq(answerIds.length, 2);
        assertEq(answerIds[0], 1); // First answer ID
        assertEq(answerIds[1], 2); // Second answer ID
        
        console.log("getQuestion with answers test passed");
    }
    
    function test_GetQuestion_SelectedAnswer() public {
        // Create a question
        vm.prank(alice);
        baseQuery.createQuestion("QmQuestionHash", USDC_AMOUNT, 0, false);
        
        // Submit answer
        vm.prank(bob);
        baseQuery.submitAnswer(1, "QmBobAnswer");
        
        // Select best answer
        vm.prank(alice);
        baseQuery.selectBestAnswer(1, 1);
        
        // Test getQuestion
        (
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
        ) = baseQuery.getQuestion(1);
        
        // Verify selected answer
        assertEq(selectedAnswerId, 1);
        assertEq(bountyAmount, USDC_AMOUNT); // Bounty amount should remain visible even after distribution
        assertFalse(isActive); // Question should be inactive after best answer is selected
        
        console.log("getQuestion selected answer test passed");
    }

    // ========== GETANSWER TESTS ==========
    
    function test_GetAnswer_Basic() public {
        // Create a question
        vm.prank(alice);
        baseQuery.createQuestion("QmQuestionHash", USDC_AMOUNT, 0, false);
        
        // Submit answer
        vm.prank(bob);
        baseQuery.submitAnswer(1, "QmBobAnswer");
        
        // Test getAnswer
        (
            uint256 id,
            uint256 questionId,
            address provider,
            string memory ipfsHash,
            uint256 timestamp,
            uint256 upvotes,
            uint256 downvotes,
            uint256 prizeAmount
        ) = baseQuery.getAnswer(1);
        
        // Verify all fields
        assertEq(id, 1);
        assertEq(questionId, 1);
        assertEq(provider, bob);
        assertEq(ipfsHash, "QmBobAnswer");
        assertGt(timestamp, 0);
        assertEq(upvotes, 0);
        assertEq(downvotes, 0);
        assertEq(prizeAmount, 0); // No prize yet, not selected
        
        console.log("getAnswer basic test passed");
    }
    
    function test_GetAnswer_WithVotes() public {
        // Create a question
        vm.prank(alice);
        baseQuery.createQuestion("QmQuestionHash", USDC_AMOUNT, 0, false);
        
        // Submit answer
        vm.prank(bob);
        baseQuery.submitAnswer(1, "QmBobAnswer");
        
        // Vote on answer
        vm.prank(charlie);
        baseQuery.vote(1, 1, IReputationSystem.ContentType.ANSWER, true);
        
        vm.prank(dave);
        baseQuery.vote(1, 1, IReputationSystem.ContentType.ANSWER, true);
        
        // Test getAnswer
        (
            uint256 id,
            uint256 questionId,
            address provider,
            string memory ipfsHash,
            uint256 timestamp,
            uint256 upvotes,
            uint256 downvotes,
            uint256 prizeAmount
        ) = baseQuery.getAnswer(1);
        
        // Verify vote counts
        assertEq(upvotes, 2);
        assertEq(downvotes, 0);
        
        console.log("getAnswer with votes test passed");
    }
    
    function test_GetAnswer_BountyPrize() public {
        // Create a question
        vm.prank(alice);
        baseQuery.createQuestion("QmQuestionHash", USDC_AMOUNT, 0, false);
        
        // Submit answer
        vm.prank(bob);
        baseQuery.submitAnswer(1, "QmBobAnswer");
        
        // Select best answer
        vm.prank(alice);
        baseQuery.selectBestAnswer(1, 1);
        
        // Test getAnswer
        (
            uint256 id,
            uint256 questionId,
            address provider,
            string memory ipfsHash,
            uint256 timestamp,
            uint256 upvotes,
            uint256 downvotes,
            uint256 prizeAmount
        ) = baseQuery.getAnswer(1);
        
        // Verify prize amount (should show the bounty amount that was earned)
        assertEq(prizeAmount, USDC_AMOUNT);
        
        console.log("getAnswer bounty prize test passed");
    }
    
    function test_GetAnswer_PoolPrize() public {
        // Create a pool question
        vm.prank(alice);
        baseQuery.createQuestion("QmPoolHash", USDC_AMOUNT, POOL_DURATION, true);
        
        // Submit answer
        vm.prank(bob);
        baseQuery.submitAnswer(1, "QmBobAnswer");
        
        // Vote on answer
        vm.prank(charlie);
        baseQuery.vote(1, 1, IReputationSystem.ContentType.ANSWER, true);
        
        // Test getAnswer before pool distribution
        (
            uint256 id,
            uint256 questionId,
            address provider,
            string memory ipfsHash,
            uint256 timestamp,
            uint256 upvotes,
            uint256 downvotes,
            uint256 prizeAmount
        ) = baseQuery.getAnswer(1);
        
        // Verify prize amount (should be calculated potential reward)
        assertGt(prizeAmount, 0); // Should have potential reward
        
        console.log("getAnswer pool prize test passed");
    }
    
    function test_GetQuestion_PoolDistributed() public {
        // Create a pool question
        vm.prank(alice);
        baseQuery.createQuestion("QmPoolHash", USDC_AMOUNT, POOL_DURATION, true);
        
        // Submit answer
        vm.prank(bob);
        baseQuery.submitAnswer(1, "QmBobAnswer");
        
        // Vote on answer
        vm.prank(charlie);
        baseQuery.vote(1, 1, IReputationSystem.ContentType.ANSWER, true);
        
        // Fast forward time to expire pool
        vm.warp(block.timestamp + POOL_DURATION + 1);
        
        // Distribute pool
        baseQuery.distributePool(1);
        
        // Test getQuestion
        (
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
        ) = baseQuery.getQuestion(1);
        
        // Verify pool is distributed and question is inactive
        assertEq(poolAmount, 0); // Pool amount should be 0 after distribution
        assertFalse(isActive); // Question should be inactive after pool distribution
        
        console.log("getQuestion pool distributed test passed");
    }

    // ========== GETALLQUESTIONS TESTS ==========
    
    function test_GetAllQuestions_Empty() public {
        // Test when no questions exist
        (
            uint256[] memory questionIds,
            string[] memory ipfsHashes,
            address[] memory creators,
            uint256[] memory amounts,
            bool[] memory isPoolQuestions,
            bool[] memory isActiveQuestions,
            uint256[] memory timestamps
        ) = baseQuery.getAllQuestions();
        
        // Verify empty arrays
        assertEq(questionIds.length, 0);
        assertEq(ipfsHashes.length, 0);
        assertEq(creators.length, 0);
        assertEq(amounts.length, 0);
        assertEq(isPoolQuestions.length, 0);
        assertEq(isActiveQuestions.length, 0);
        assertEq(timestamps.length, 0);
        
        console.log("getAllQuestions empty test passed");
    }
    
    function test_GetAllQuestions_SingleBounty() public {
        // Create a bounty question
        vm.prank(alice);
        baseQuery.createQuestion("QmBountyHash", USDC_AMOUNT, 0, false);
        
        // Test getAllQuestions
        (
            uint256[] memory questionIds,
            string[] memory ipfsHashes,
            address[] memory creators,
            uint256[] memory amounts,
            bool[] memory isPoolQuestions,
            bool[] memory isActiveQuestions,
            uint256[] memory timestamps
        ) = baseQuery.getAllQuestions();
        
        // Verify single question
        assertEq(questionIds.length, 1);
        assertEq(questionIds[0], 1);
        assertEq(ipfsHashes[0], "QmBountyHash");
        assertEq(creators[0], alice);
        assertEq(amounts[0], USDC_AMOUNT);
        assertFalse(isPoolQuestions[0]);
        assertTrue(isActiveQuestions[0]); // New question should be active
        assertGt(timestamps[0], 0);
        
        console.log("getAllQuestions single bounty test passed");
    }
    
    function test_GetAllQuestions_SinglePool() public {
        // Create a pool question
        vm.prank(alice);
        baseQuery.createQuestion("QmPoolHash", USDC_AMOUNT, POOL_DURATION, true);
        
        // Test getAllQuestions
        (
            uint256[] memory questionIds,
            string[] memory ipfsHashes,
            address[] memory creators,
            uint256[] memory amounts,
            bool[] memory isPoolQuestions,
            bool[] memory isActiveQuestions,
            uint256[] memory timestamps
        ) = baseQuery.getAllQuestions();
        
        // Verify single pool question
        assertEq(questionIds.length, 1);
        assertEq(questionIds[0], 1);
        assertEq(ipfsHashes[0], "QmPoolHash");
        assertEq(creators[0], alice);
        assertEq(amounts[0], USDC_AMOUNT);
        assertTrue(isPoolQuestions[0]);
        assertTrue(isActiveQuestions[0]); // New pool question should be active
        assertGt(timestamps[0], 0);
        
        console.log("getAllQuestions single pool test passed");
    }
    
    function test_GetAllQuestions_MultipleMixed() public {
        // Create multiple questions
        vm.prank(alice);
        baseQuery.createQuestion("QmBounty1", USDC_AMOUNT, 0, false);
        
        vm.prank(bob);
        baseQuery.createQuestion("QmPool1", USDC_AMOUNT * 2, POOL_DURATION, true);
        
        vm.prank(charlie);
        baseQuery.createQuestion("QmBounty2", USDC_AMOUNT * 3, 0, false);
        
        // Test getAllQuestions
        (
            uint256[] memory questionIds,
            string[] memory ipfsHashes,
            address[] memory creators,
            uint256[] memory amounts,
            bool[] memory isPoolQuestions,
            bool[] memory isActiveQuestions,
            uint256[] memory timestamps
        ) = baseQuery.getAllQuestions();
        
        // Verify 3 questions
        assertEq(questionIds.length, 3);
        
        // Question 1: Bounty
        assertEq(questionIds[0], 1);
        assertEq(ipfsHashes[0], "QmBounty1");
        assertEq(creators[0], alice);
        assertEq(amounts[0], USDC_AMOUNT);
        assertFalse(isPoolQuestions[0]);
        assertTrue(isActiveQuestions[0]); // New bounty question should be active
        
        // Question 2: Pool
        assertEq(questionIds[1], 2);
        assertEq(ipfsHashes[1], "QmPool1");
        assertEq(creators[1], bob);
        assertEq(amounts[1], USDC_AMOUNT * 2);
        assertTrue(isPoolQuestions[1]);
        assertTrue(isActiveQuestions[1]); // New pool question should be active
        
        // Question 3: Bounty
        assertEq(questionIds[2], 3);
        assertEq(ipfsHashes[2], "QmBounty2");
        assertEq(creators[2], charlie);
        assertEq(amounts[2], USDC_AMOUNT * 3);
        assertFalse(isPoolQuestions[2]);
        assertTrue(isActiveQuestions[2]); // New bounty question should be active
        
        console.log("getAllQuestions multiple mixed test passed");
    }
    
    function test_GetAllQuestions_ArrayConsistency() public {
        // Create a question
        vm.prank(alice);
        baseQuery.createQuestion("QmTestHash", USDC_AMOUNT, 0, false);
        
        // Test getAllQuestions
        (
            uint256[] memory questionIds,
            string[] memory ipfsHashes,
            address[] memory creators,
            uint256[] memory amounts,
            bool[] memory isPoolQuestions,
            bool[] memory isActiveQuestions,
            uint256[] memory timestamps
        ) = baseQuery.getAllQuestions();
        
        // Verify all arrays have the same length
        uint256 length = questionIds.length;
        assertEq(ipfsHashes.length, length);
        assertEq(creators.length, length);
        assertEq(amounts.length, length);
        assertEq(isPoolQuestions.length, length);
        assertEq(isActiveQuestions.length, length);
        assertEq(timestamps.length, length);
        
        console.log("getAllQuestions array consistency test passed");
    }
    
    function test_GetAllQuestions_WithInactiveQuestions() public {
        // Create a bounty question
        vm.prank(alice);
        baseQuery.createQuestion("QmBountyHash", USDC_AMOUNT, 0, false);
        
        // Submit answer
        vm.prank(bob);
        baseQuery.submitAnswer(1, "QmBobAnswer");
        
        // Select best answer (this will make the question inactive)
        vm.prank(alice);
        baseQuery.selectBestAnswer(1, 1);
        
        // Create another active question
        vm.prank(charlie);
        baseQuery.createQuestion("QmActiveHash", USDC_AMOUNT * 2, 0, false);
        
        // Test getAllQuestions
        (
            uint256[] memory questionIds,
            string[] memory ipfsHashes,
            address[] memory creators,
            uint256[] memory amounts,
            bool[] memory isPoolQuestions,
            bool[] memory isActiveQuestions,
            uint256[] memory timestamps
        ) = baseQuery.getAllQuestions();
        
        // Verify 2 questions
        assertEq(questionIds.length, 2);
        
        // Question 1: Inactive (bounty distributed)
        assertEq(questionIds[0], 1);
        assertFalse(isActiveQuestions[0]); // Should be inactive
        
        // Question 2: Active
        assertEq(questionIds[1], 2);
        assertTrue(isActiveQuestions[1]); // Should be active
        
        console.log("getAllQuestions with inactive questions test passed");
    }
}
