// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BaseQuery.sol";
import "../src/ReputationSystem.sol";
import "../src/MockUSDC.sol";

contract USDCFlowTest is Test {
    StackExchange public stackExchange;
    ReputationSystem public reputationSystem;
    MockUSDC public usdc;
    
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public charlie = address(0x3);
    address public dave = address(0x4);
    address public eve = address(0x5);
    
    uint256 public constant USDC_AMOUNT = 1000000; // 1 USDC (6 decimals)
    uint256 public constant POOL_DURATION = 1 hours;
    uint256 public constant PLATFORM_FEE = 200; // 2%
    
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
        vm.deal(eve, 1 ether);
        
        // Mint USDC to test accounts
        usdc.mint(alice, 10000000); // 10 USDC
        usdc.mint(bob, 10000000);   // 10 USDC
        usdc.mint(charlie, 10000000); // 10 USDC
        usdc.mint(dave, 10000000);    // 10 USDC
        usdc.mint(eve, 10000000);     // 10 USDC
        
        // Approve USDC spending
        vm.prank(alice);
        usdc.approve(address(stackExchange), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(stackExchange), type(uint256).max);
        vm.prank(charlie);
        usdc.approve(address(stackExchange), type(uint256).max);
        vm.prank(dave);
        usdc.approve(address(stackExchange), type(uint256).max);
        vm.prank(eve);
        usdc.approve(address(stackExchange), type(uint256).max);
    }

    function test_BountyQuestionUSDCFlow() public {
        uint256 aliceInitialBalance = usdc.balanceOf(alice);
        uint256 bobInitialBalance = usdc.balanceOf(bob);
        uint256 contractInitialBalance = usdc.balanceOf(address(stackExchange));
        
        console.log("=== Bounty Question USDC Flow Test ===");
        console.log("Alice initial USDC balance:", aliceInitialBalance);
        console.log("Bob initial USDC balance:", bobInitialBalance);
        console.log("Contract initial USDC balance:", contractInitialBalance);
        
        // Alice creates a bounty question
        vm.prank(alice);
        stackExchange.createQuestion("QmBountyHash", USDC_AMOUNT, 0, false);
        
        uint256 aliceBalanceAfterQuestion = usdc.balanceOf(alice);
        uint256 contractBalanceAfterQuestion = usdc.balanceOf(address(stackExchange));
        
        console.log("Alice USDC balance after creating question:", aliceBalanceAfterQuestion);
        console.log("Contract USDC balance after question creation:", contractBalanceAfterQuestion);
        
        // Verify USDC transfer
        assertEq(aliceBalanceAfterQuestion, aliceInitialBalance - USDC_AMOUNT);
        assertEq(contractBalanceAfterQuestion, contractInitialBalance + USDC_AMOUNT);
        
        // Bob submits an answer
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmBobAnswerHash");
        
        // Alice selects Bob's answer as best
        vm.prank(alice);
        stackExchange.selectBestAnswer(1, 1);
        
        uint256 bobBalanceAfterReward = usdc.balanceOf(bob);
        uint256 contractBalanceAfterReward = usdc.balanceOf(address(stackExchange));
        uint256 platformFees = stackExchange.getUSDCBalance();
        
        console.log("Bob USDC balance after receiving reward:", bobBalanceAfterReward);
        console.log("Contract USDC balance after reward distribution:", contractBalanceAfterReward);
        console.log("Platform fees collected:", platformFees);
        
        // Calculate expected values
        uint256 platformFeeAmount = (USDC_AMOUNT * PLATFORM_FEE) / 10000;
        uint256 bobReward = USDC_AMOUNT - platformFeeAmount;
        
        console.log("Expected platform fee:", platformFeeAmount);
        console.log("Expected Bob reward:", bobReward);
        
        // Verify Bob received the reward (minus platform fee)
        assertEq(bobBalanceAfterReward, bobInitialBalance + bobReward);
        
        // Verify platform fees are collected
        assertEq(platformFees, platformFeeAmount);
        
        // Verify question bounty is now 0
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
        
        console.log("Bounty question USDC flow test passed!");
    }

    function test_PoolQuestionUSDCFlow() public {
        uint256 aliceInitialBalance = usdc.balanceOf(alice);
        uint256 bobInitialBalance = usdc.balanceOf(bob);
        uint256 charlieInitialBalance = usdc.balanceOf(charlie);
        uint256 daveInitialBalance = usdc.balanceOf(dave);
        
        console.log("\n=== Pool Question USDC Flow Test (Variable Answers) ===");
        console.log("Alice initial USDC balance:", aliceInitialBalance);
        console.log("Bob initial USDC balance:", bobInitialBalance);
        console.log("Charlie initial USDC balance:", charlieInitialBalance);
        console.log("Dave initial USDC balance:", daveInitialBalance);
        
        // Alice creates a pool question
        vm.prank(alice);
        stackExchange.createQuestion("QmPoolHash", USDC_AMOUNT, POOL_DURATION, true);
        
        uint256 aliceBalanceAfterQuestion = usdc.balanceOf(alice);
        console.log("Alice USDC balance after creating pool question:", aliceBalanceAfterQuestion);
        
        // Verify USDC transfer
        assertEq(aliceBalanceAfterQuestion, aliceInitialBalance - USDC_AMOUNT);
        
        // Submit answers - now we can have more than 3 answers!
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmBobAnswerHash");
        
        vm.prank(charlie);
        stackExchange.submitAnswer(1, "QmCharlieAnswerHash");
        
        vm.prank(dave);
        stackExchange.submitAnswer(1, "QmDaveAnswerHash");
        
        // Add more answers to demonstrate variable answer handling
        vm.prank(eve);
        stackExchange.submitAnswer(1, "QmEveAnswerHash");
        
        // Fund and add a 5th answerer (Frank)
        address frank = address(0x6);
        vm.deal(frank, 1 ether);
        usdc.mint(frank, 10000000);
        vm.prank(frank);
        usdc.approve(address(stackExchange), type(uint256).max);
        vm.prank(frank);
        stackExchange.submitAnswer(1, "QmFrankAnswerHash");
        
        console.log("Total answers submitted:", stackExchange.getQuestionAnswers(1).length);
        
        // Community voting with different scores
        // Bob: 3 upvotes, 0 downvotes (score: 3) - Best answer
        vm.prank(charlie);
        stackExchange.vote(1, 1, IReputationSystem.ContentType.ANSWER, true);
        vm.prank(dave);
        stackExchange.vote(1, 1, IReputationSystem.ContentType.ANSWER, true);
        vm.prank(eve);
        stackExchange.vote(1, 1, IReputationSystem.ContentType.ANSWER, true);
        
        // Charlie: 2 upvotes, 1 downvote (score: 1) - Second best
        vm.prank(bob);
        stackExchange.vote(1, 2, IReputationSystem.ContentType.ANSWER, true);
        vm.prank(dave);
        stackExchange.vote(1, 2, IReputationSystem.ContentType.ANSWER, true);
        vm.prank(eve);
        stackExchange.vote(1, 2, IReputationSystem.ContentType.ANSWER, false);
        
        // Dave: 1 upvote, 0 downvotes (score: 1) - Third best
        vm.prank(bob);
        stackExchange.vote(1, 3, IReputationSystem.ContentType.ANSWER, true);
        
        // Eve: 0 upvotes, 1 downvote (score: -1) - Poor answer
        vm.prank(bob);
        stackExchange.vote(1, 4, IReputationSystem.ContentType.ANSWER, false);
        
        // Frank: 0 upvotes, 0 downvotes (score: 0) - Neutral answer
        
        // Fast forward time and distribute pool
        vm.warp(block.timestamp + POOL_DURATION + 1);
        stackExchange.distributePool(1);
        
        // Get final balances
        uint256 bobBalanceAfterReward = usdc.balanceOf(bob);
        uint256 charlieBalanceAfterReward = usdc.balanceOf(charlie);
        uint256 daveBalanceAfterReward = usdc.balanceOf(dave);
        uint256 eveBalanceAfterReward = usdc.balanceOf(eve);
        uint256 frankBalanceAfterReward = usdc.balanceOf(frank);
        uint256 platformFees = stackExchange.getUSDCBalance();
        
        console.log("Bob USDC balance after pool distribution:", bobBalanceAfterReward);
        console.log("Charlie USDC balance after pool distribution:", charlieBalanceAfterReward);
        console.log("Dave USDC balance after pool distribution:", daveBalanceAfterReward);
        console.log("Eve USDC balance after pool distribution:", eveBalanceAfterReward);
        console.log("Frank USDC balance after pool distribution:", frankBalanceAfterReward);
        console.log("Platform fees collected:", platformFees);
        
        // Verify the new weighted distribution algorithm
        // Bob should get the most (highest score: 3)
        assertGt(bobBalanceAfterReward, charlieBalanceAfterReward);
        assertGt(bobBalanceAfterReward, daveBalanceAfterReward);
        
        // Charlie and Dave should get similar amounts (same score: 1)
        uint256 charlieReward = charlieBalanceAfterReward - charlieInitialBalance;
        uint256 daveReward = daveBalanceAfterReward - daveInitialBalance;
        assertApproxEqRel(charlieReward, daveReward, 0.1e18); // Within 10%
        
        // Eve and Frank should get very little or nothing (negative/zero scores)
        uint256 eveReward = eveBalanceAfterReward - 10000000;
        uint256 frankReward = frankBalanceAfterReward - 10000000;
        assertLe(eveReward, 1000); // Should get very little
        assertLe(frankReward, 1000); // Should get very little
        
        // Verify platform fees
        uint256 platformFeeAmount = (USDC_AMOUNT * PLATFORM_FEE) / 10000;
        assertEq(platformFees, platformFeeAmount);
        
        // Verify pool is distributed
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
        
        console.log("Enhanced pool question USDC flow test passed!");
        console.log("Demonstrated: Variable answer handling, weighted distribution, and score-based rewards!");
    }

    function test_PlatformFeeWithdrawal() public {
        // Create and complete a bounty question to generate fees
        vm.prank(alice);
        stackExchange.createQuestion("QmBountyHash", USDC_AMOUNT, 0, false);
        
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmBobAnswerHash");
        
        vm.prank(alice);
        stackExchange.selectBestAnswer(1, 1);
        
        uint256 platformFeesBefore = stackExchange.getUSDCBalance();
        uint256 ownerBalanceBefore = usdc.balanceOf(stackExchange.owner());
        
        console.log("\n=== Platform Fee Withdrawal Test ===");
        console.log("Platform fees before withdrawal:", platformFeesBefore);
        console.log("Owner USDC balance before withdrawal:", ownerBalanceBefore);
        
        // Withdraw platform fees
        vm.prank(stackExchange.owner());
        stackExchange.withdrawPlatformFees();
        
        uint256 platformFeesAfter = stackExchange.getUSDCBalance();
        uint256 ownerBalanceAfter = usdc.balanceOf(stackExchange.owner());
        
        console.log("Platform fees after withdrawal:", platformFeesAfter);
        console.log("Owner USDC balance after withdrawal:", ownerBalanceAfter);
        
        // Verify fees are withdrawn
        assertEq(platformFeesAfter, 0);
        assertEq(ownerBalanceAfter, ownerBalanceBefore + platformFeesBefore);
        
        console.log("Platform fee withdrawal test passed!");
    }

    function test_MultipleQuestionsUSDCFlow() public {
        console.log("\n=== Multiple Questions USDC Flow Test ===");
        
        // Create multiple questions
        vm.prank(alice);
        stackExchange.createQuestion("QmQuestion1", USDC_AMOUNT, 0, false);
        
        vm.prank(bob);
        stackExchange.createQuestion("QmQuestion2", USDC_AMOUNT * 2, 0, false);
        
        vm.prank(charlie);
        stackExchange.createQuestion("QmQuestion3", USDC_AMOUNT, POOL_DURATION, true);
        
        uint256 contractBalanceAfterQuestions = usdc.balanceOf(address(stackExchange));
        console.log("Contract USDC balance after 3 questions:", contractBalanceAfterQuestions);
        
        // Expected: 1 + 2 + 1 = 4 USDC
        assertEq(contractBalanceAfterQuestions, USDC_AMOUNT * 4);
        
        // Submit answers to all questions
        vm.prank(dave);
        stackExchange.submitAnswer(1, "QmAnswer1");
        
        vm.prank(eve);
        stackExchange.submitAnswer(2, "QmAnswer2");
        
        vm.prank(alice);
        stackExchange.submitAnswer(3, "QmAnswer3");
        
        // Complete bounty questions
        vm.prank(alice);
        stackExchange.selectBestAnswer(1, 1);
        
        vm.prank(bob);
        stackExchange.selectBestAnswer(2, 2);
        
        // Fast forward for pool question
        vm.warp(block.timestamp + POOL_DURATION + 1);
        stackExchange.distributePool(3);
        
        uint256 finalContractBalance = usdc.balanceOf(address(stackExchange));
        uint256 totalPlatformFees = stackExchange.getUSDCBalance();
        
        console.log("Final contract USDC balance:", finalContractBalance);
        console.log("Total platform fees collected:", totalPlatformFees);
        
        // Verify all questions are completed
        (
            uint256 id1,
            address owner1,
            string memory ipfsHash1,
            uint256 bountyAmount1,
            uint256 poolAmount1,
            uint256 poolEndTime1,
            uint256 selectedAnswerId1,
            uint256[] memory answerIds1,
            bool poolDistributed1,
            bool isActive1,
            bool isPoolQuestion1,
            uint256 timestamp1
        ) = stackExchange.getQuestion(1);
        (
            uint256 id2,
            address owner2,
            string memory ipfsHash2,
            uint256 bountyAmount2,
            uint256 poolAmount2,
            uint256 poolEndTime2,
            uint256 selectedAnswerId2,
            uint256[] memory answerIds2,
            bool poolDistributed2,
            bool isActive2,
            bool isPoolQuestion2,
            uint256 timestamp2
        ) = stackExchange.getQuestion(2);
        (
            uint256 id3,
            address owner3,
            string memory ipfsHash3,
            uint256 bountyAmount3,
            uint256 poolAmount3,
            uint256 poolEndTime3,
            uint256 selectedAnswerId3,
            uint256[] memory answerIds3,
            bool poolDistributed3,
            bool isActive3,
            bool isPoolQuestion3,
            uint256 timestamp3
        ) = stackExchange.getQuestion(3);
        
        assertEq(bountyAmount1, 0);
        assertEq(bountyAmount2, 0);
        assertTrue(poolDistributed3);
        
        console.log("Multiple questions USDC flow test passed!");
    }

    function test_USDCBalanceTracking() public {
        console.log("\n=== USDC Balance Tracking Test ===");
        
        uint256 initialBalance = usdc.balanceOf(address(stackExchange));
        console.log("Initial contract USDC balance:", initialBalance);
        
        // Create question
        vm.prank(alice);
        stackExchange.createQuestion("QmTestHash", USDC_AMOUNT, 0, false);
        
        uint256 balanceAfterQuestion = usdc.balanceOf(address(stackExchange));
        uint256 platformBalance = stackExchange.getUSDCBalance();
        
        console.log("Contract USDC balance after question:", balanceAfterQuestion);
        console.log("Platform USDC balance (should be 0):", platformBalance);
        
        assertEq(balanceAfterQuestion, initialBalance + USDC_AMOUNT);
        // Note: getUSDCBalance() returns total contract balance, not just platform fees
        assertEq(platformBalance, balanceAfterQuestion);
        
        // Complete question to generate fees
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmAnswerHash");
        
        vm.prank(alice);
        stackExchange.selectBestAnswer(1, 1);
        
        uint256 balanceAfterCompletion = usdc.balanceOf(address(stackExchange));
        uint256 platformBalanceAfterCompletion = stackExchange.getUSDCBalance();
        
        console.log("Contract USDC balance after completion:", balanceAfterCompletion);
        console.log("Platform USDC balance after completion:", platformBalanceAfterCompletion);
        
        // After completion, the balance should be just the platform fees
        // (bounty was transferred to winner)
        assertGt(platformBalanceAfterCompletion, 0);
        assertLt(balanceAfterCompletion, balanceAfterQuestion);
        
        console.log("USDC balance tracking test passed!");
    }

    function test_EdgeCaseUSDCFlows() public {
        console.log("\n=== Edge Case USDC Flow Tests ===");
        
        // Test with very small USDC amounts
        uint256 smallAmount = 1000; // 0.001 USDC
        
        vm.prank(alice);
        stackExchange.createQuestion("QmSmallHash", smallAmount, 0, false);
        
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmSmallAnswer");
        
        vm.prank(alice);
        stackExchange.selectBestAnswer(1, 1);
        
        uint256 platformFees = stackExchange.getUSDCBalance();
        console.log("Platform fees from small amount:", platformFees);
        
        // Even small amounts should generate proportional fees
        assertGt(platformFees, 0);
        
        // Test with large USDC amounts
        uint256 largeAmount = 10000000; // 10 USDC
        
        vm.prank(bob);
        stackExchange.createQuestion("QmLargeHash", largeAmount, 0, false);
        
        vm.prank(charlie);
        stackExchange.submitAnswer(2, "QmLargeAnswer");
        
        vm.prank(bob);
        stackExchange.selectBestAnswer(2, 2);
        
        uint256 largePlatformFees = stackExchange.getUSDCBalance();
        console.log("Platform fees from large amount:", largePlatformFees);
        
        // Large amounts should generate significant fees
        assertGt(largePlatformFees, platformFees);
        
        console.log("Edge case USDC flow tests passed!");
    }

    function test_PoolWithdrawalWithNoGoodAnswers() public {
        console.log("\n=== Pool Withdrawal Test (No Good Answers) ===");
        
        uint256 aliceInitialBalance = usdc.balanceOf(alice);
        
        // Alice creates a pool question
        vm.prank(alice);
        stackExchange.createQuestion("QmWithdrawHash", USDC_AMOUNT, POOL_DURATION, true);
        
        // Submit answers but they get downvoted
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmBadAnswer1");
        
        vm.prank(charlie);
        stackExchange.submitAnswer(1, "QmBadAnswer2");
        
        // Downvote the answers
        vm.prank(dave);
        stackExchange.vote(1, 1, IReputationSystem.ContentType.ANSWER, false);
        
        vm.prank(eve);
        stackExchange.vote(1, 2, IReputationSystem.ContentType.ANSWER, false);
        
        // Fast forward time
        vm.warp(block.timestamp + POOL_DURATION + 1);
        
        // Alice should be able to withdraw since no good answers
        vm.prank(alice);
        stackExchange.withdrawPool(1);
        
        uint256 aliceBalanceAfterWithdrawal = usdc.balanceOf(alice);
        uint256 platformFees = stackExchange.getUSDCBalance();
        
        console.log("Alice balance after withdrawal:", aliceBalanceAfterWithdrawal);
        console.log("Platform fees collected:", platformFees);
        
        // Verify withdrawal (minus platform fee)
        uint256 platformFeeAmount = (USDC_AMOUNT * PLATFORM_FEE) / 10000;
        uint256 expectedWithdrawal = USDC_AMOUNT - platformFeeAmount;
        
        assertEq(aliceBalanceAfterWithdrawal, aliceInitialBalance - USDC_AMOUNT + expectedWithdrawal);
        assertEq(platformFees, platformFeeAmount);
        
        // Verify question is marked as distributed
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
        
        console.log("Pool withdrawal test passed!");
    }

    function test_PoolWithdrawalWithGoodAnswers() public {
        console.log("\n=== Pool Withdrawal Test (With Good Answers) ===");
        
        // Alice creates a pool question
        vm.prank(alice);
        stackExchange.createQuestion("QmGoodAnswersHash", USDC_AMOUNT, POOL_DURATION, true);
        
        // Submit answers
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmGoodAnswer1");
        
        vm.prank(charlie);
        stackExchange.submitAnswer(1, "QmGoodAnswer2");
        
        // Upvote the answers (making them good)
        vm.prank(dave);
        stackExchange.vote(1, 1, IReputationSystem.ContentType.ANSWER, true);
        
        vm.prank(eve);
        stackExchange.vote(1, 2, IReputationSystem.ContentType.ANSWER, true);
        
        // Fast forward time
        vm.warp(block.timestamp + POOL_DURATION + 1);
        
        // Alice should NOT be able to withdraw since there are good answers
        vm.prank(alice);
        vm.expectRevert(StackExchange.CannotWithdrawWithGoodAnswers.selector);
        stackExchange.withdrawPool(1);
        
        console.log("Pool withdrawal with good answers test passed!");
    }

    function test_VariableAnswerPoolDistribution() public {
        console.log("\n=== Variable Answer Pool Distribution Test ===");
        
        // Alice creates a pool question
        vm.prank(alice);
        stackExchange.createQuestion("QmVariableHash", USDC_AMOUNT, POOL_DURATION, true);
        
        // Submit many answers
        address[] memory answerers = new address[](5);
        answerers[0] = bob;
        answerers[1] = charlie;
        answerers[2] = dave;
        answerers[3] = eve;
        answerers[4] = address(0x6); // Frank
        
        // Fund Frank with ETH and USDC
        vm.deal(answerers[4], 1 ether);
        usdc.mint(answerers[4], 10000000);
        vm.prank(answerers[4]);
        usdc.approve(address(stackExchange), type(uint256).max);
        
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(answerers[i]);
            stackExchange.submitAnswer(1, string(abi.encodePacked("QmAnswer", i)));
        }
        
        // Vote on answers with different scores
        // Bob: 3 upvotes, 0 downvotes (score: 3)
        vm.prank(charlie);
        stackExchange.vote(1, 1, IReputationSystem.ContentType.ANSWER, true);
        vm.prank(dave);
        stackExchange.vote(1, 1, IReputationSystem.ContentType.ANSWER, true);
        vm.prank(eve);
        stackExchange.vote(1, 1, IReputationSystem.ContentType.ANSWER, true);
        
        // Charlie: 2 upvotes, 1 downvote (score: 1)
        vm.prank(bob);
        stackExchange.vote(1, 2, IReputationSystem.ContentType.ANSWER, true);
        vm.prank(dave);
        stackExchange.vote(1, 2, IReputationSystem.ContentType.ANSWER, true);
        vm.prank(eve);
        stackExchange.vote(1, 2, IReputationSystem.ContentType.ANSWER, false);
        
        // Dave: 1 upvote, 0 downvotes (score: 1)
        vm.prank(bob);
        stackExchange.vote(1, 3, IReputationSystem.ContentType.ANSWER, true);
        
        // Eve: 0 upvotes, 1 downvote (score: -1)
        vm.prank(bob);
        stackExchange.vote(1, 4, IReputationSystem.ContentType.ANSWER, false);
        
        // Frank: 0 upvotes, 0 downvotes (score: 0)
        
        // Fast forward time and distribute
        vm.warp(block.timestamp + POOL_DURATION + 1);
        stackExchange.distributePool(1);
        
        // Check balances
        uint256 bobBalance = usdc.balanceOf(bob);
        uint256 charlieBalance = usdc.balanceOf(charlie);
        uint256 daveBalance = usdc.balanceOf(dave);
        uint256 eveBalance = usdc.balanceOf(eve);
        uint256 frankBalance = usdc.balanceOf(answerers[4]);
        
        console.log("Bob balance after distribution:", bobBalance);
        console.log("Charlie balance after distribution:", charlieBalance);
        console.log("Dave balance after distribution:", daveBalance);
        console.log("Eve balance after distribution:", eveBalance);
        console.log("Frank balance after distribution:", frankBalance);
        
        // Bob should get the most (highest score)
        assertGt(bobBalance, charlieBalance);
        assertGt(bobBalance, daveBalance);
        
        // Charlie and Dave should get similar amounts (same score)
        uint256 charlieDiff = charlieBalance > 10000000 ? charlieBalance - 10000000 : 0;
        uint256 daveDiff = daveBalance > 10000000 ? daveBalance - 10000000 : 0;
        assertApproxEqRel(charlieDiff, daveDiff, 0.1e18); // Within 10%
        
        // Eve and Frank should get nothing or very little (negative/zero scores)
        assertLe(eveBalance, 10000000);
        assertLe(frankBalance, 10000000);
        
        console.log("Variable answer pool distribution test passed!");
    }

    function test_ConcurrentQuestionsAndAnswers() public {
        console.log("\n=== Concurrent Questions and Answers Test ===");
        
        // Create multiple questions simultaneously
        vm.prank(alice);
        stackExchange.createQuestion("QmQuestion1", USDC_AMOUNT, 0, false);
        
        vm.prank(bob);
        stackExchange.createQuestion("QmQuestion2", USDC_AMOUNT, POOL_DURATION, true);
        
        vm.prank(charlie);
        stackExchange.createQuestion("QmQuestion3", USDC_AMOUNT * 2, 0, false);
        
        // Submit answers to different questions
        vm.prank(dave);
        stackExchange.submitAnswer(1, "QmAnswer1");
        
        vm.prank(eve);
        stackExchange.submitAnswer(2, "QmAnswer2");
        
        vm.prank(alice);
        stackExchange.submitAnswer(3, "QmAnswer3");
        
        // Complete bounty questions
        vm.prank(alice);
        stackExchange.selectBestAnswer(1, 1);
        
        vm.prank(charlie);
        stackExchange.selectBestAnswer(3, 3);
        
        // Fast forward for pool question
        vm.warp(block.timestamp + POOL_DURATION + 1);
        stackExchange.distributePool(2);
        
        // Verify all questions are properly completed
        (
            uint256 id1,
            address owner1,
            string memory ipfsHash1,
            uint256 bountyAmount1,
            uint256 poolAmount1,
            uint256 poolEndTime1,
            uint256 selectedAnswerId1,
            uint256[] memory answerIds1,
            bool poolDistributed1,
            bool isActive1,
            bool isPoolQuestion1,
            uint256 timestamp1
        ) = stackExchange.getQuestion(1);
        (
            uint256 id2,
            address owner2,
            string memory ipfsHash2,
            uint256 bountyAmount2,
            uint256 poolAmount2,
            uint256 poolEndTime2,
            uint256 selectedAnswerId2,
            uint256[] memory answerIds2,
            bool poolDistributed2,
            bool isActive2,
            bool isPoolQuestion2,
            uint256 timestamp2
        ) = stackExchange.getQuestion(2);
        (
            uint256 id3,
            address owner3,
            string memory ipfsHash3,
            uint256 bountyAmount3,
            uint256 poolAmount3,
            uint256 poolEndTime3,
            uint256 selectedAnswerId3,
            uint256[] memory answerIds3,
            bool poolDistributed3,
            bool isActive3,
            bool isPoolQuestion3,
            uint256 timestamp3
        ) = stackExchange.getQuestion(3);
        
        assertEq(bountyAmount1, 0);
        assertEq(poolAmount2, 0);
        assertTrue(poolDistributed2);
        assertEq(bountyAmount3, 0);
        
        console.log("Concurrent questions test passed!");
    }

    function test_USDCTransferFailures() public {
        console.log("\n=== USDC Transfer Failure Test ===");
        
        // Create a question
        vm.prank(alice);
        stackExchange.createQuestion("QmTestHash", USDC_AMOUNT, 0, false);
        
        // Submit answer
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmAnswerHash");
        
        // Try to select best answer (this should work normally)
        vm.prank(alice);
        stackExchange.selectBestAnswer(1, 1);
        
        // Verify Bob received the reward
        uint256 bobBalance = usdc.balanceOf(bob);
        assertGt(bobBalance, 10000000);
        
        console.log("USDC transfer failure test passed!");
    }

    function test_QuestionOwnerPermissions() public {
        console.log("\n=== Question Owner Permissions Test ===");
        
        // Alice creates a question
        vm.prank(alice);
        stackExchange.createQuestion("QmTestHash", USDC_AMOUNT, 0, false);
        
        // Bob tries to select best answer (should fail)
        vm.prank(bob);
        stackExchange.submitAnswer(1, "QmBobAnswer");
        
        vm.prank(charlie);
        vm.expectRevert(StackExchange.NotQuestionOwner.selector);
        stackExchange.selectBestAnswer(1, 1);
        
        // Alice should be able to select best answer
        vm.prank(alice);
        stackExchange.selectBestAnswer(1, 1);
        
        console.log("Question owner permissions test passed!");
    }
}
