// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ReputationSystem.sol";
import "../src/BaseQuery.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Base Sepolia USDC address 
        address baseSepoliaUSDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Deploying ReputationSystem...");
        ReputationSystem reputationSystem = new ReputationSystem();
        console.log("ReputationSystem deployed at:", address(reputationSystem));
        
        console.log("Deploying BaseQuery...");
        BaseQuery baseQuery = new BaseQuery(address(reputationSystem), baseSepoliaUSDC);
        console.log("BaseQuery deployed at:", address(baseQuery));
        
        // Set up authorization
        reputationSystem.setAuthorizedCaller(address(baseQuery), true);
        console.log("Authorization set up complete");
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("Network: Base Sepolia");
        console.log("Deployer:", deployer);
        console.log("ReputationSystem:", address(reputationSystem));
        console.log("BaseQuery:", address(baseQuery));
        console.log("USDC:", baseSepoliaUSDC);
        console.log("========================\n");
    }
}
