// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AgentPayGuard} from "../src/AgentPayGuard.sol";
import {MockUSD8} from "../src/mocks/MockUSD8.sol";

contract AgentPayGuardTest is Test {
    AgentPayGuard guard;
    MockUSD8 token;
    address owner = makeAddr("owner");
    address agent = makeAddr("agent");
    address shop = makeAddr("shop");
    address attacker = makeAddr("attacker");
    bytes32 constant O1 = keccak256("order-1");
    bytes32 constant O2 = keccak256("order-2");

    function setUp() public {
        token = new MockUSD8();
        guard = new AgentPayGuard(IERC20(address(token)));
        token.mint(owner, 1000e6);
        vm.startPrank(owner);
        token.approve(address(guard), type(uint256).max);
        guard.setMandate(agent, 100e6, 30e6, uint64(block.timestamp + 1 days));
        guard.setMerchant(agent, shop, true);
        vm.stopPrank();
    }

    function test_pay_ok_movesFundsAndTracksSpend() public {
        vm.prank(agent);
        guard.pay(owner, shop, 20e6, O1);
        assertEq(token.balanceOf(shop), 20e6);
        assertEq(guard.remaining(owner, agent), 80e6);
        assertTrue(guard.orderPaid(owner, O1));
    }

    function test_attack_unlistedMerchantReverts() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentPayGuard.MerchantNotAllowed.selector, attacker));
        guard.pay(owner, attacker, 1e6, O1);
        assertEq(token.balanceOf(attacker), 0);
    }

    function test_attack_overPerTxCapReverts() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentPayGuard.OverPerTxCap.selector, 31e6, 30e6));
        guard.pay(owner, shop, 31e6, O1);
    }

    function test_attack_drainInSmallPiecesHitsBudget() public {
        vm.startPrank(agent);
        guard.pay(owner, shop, 30e6, keccak256("a"));
        guard.pay(owner, shop, 30e6, keccak256("b"));
        guard.pay(owner, shop, 30e6, keccak256("c"));
        vm.expectRevert(abi.encodeWithSelector(AgentPayGuard.OverBudget.selector, 30e6, 10e6));
        guard.pay(owner, shop, 30e6, keccak256("d"));
        vm.stopPrank();
        assertEq(token.balanceOf(shop), 90e6);
    }

    function test_replaySameOrderReverts() public {
        vm.startPrank(agent);
        guard.pay(owner, shop, 5e6, O1);
        vm.expectRevert(abi.encodeWithSelector(AgentPayGuard.OrderAlreadyPaid.selector, O1));
        guard.pay(owner, shop, 5e6, O1);
        vm.stopPrank();
    }

    function test_expiredReverts() public {
        vm.warp(block.timestamp + 1 days);
        vm.prank(agent);
        vm.expectRevert(AgentPayGuard.Expired.selector);
        guard.pay(owner, shop, 1e6, O1);
    }

    function test_revokeStopsPayments() public {
        vm.prank(owner);
        guard.revoke(agent);
        vm.prank(agent);
        vm.expectRevert(AgentPayGuard.Revoked.selector);
        guard.pay(owner, shop, 1e6, O1);
    }

    function test_strangerWithoutMandateReverts() public {
        vm.prank(attacker);
        vm.expectRevert(AgentPayGuard.NoMandate.selector);
        guard.pay(owner, attacker, 1e6, O1);
    }

    function test_removingMerchantBlocksIt() public {
        vm.prank(owner);
        guard.setMerchant(agent, shop, false);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentPayGuard.MerchantNotAllowed.selector, shop));
        guard.pay(owner, shop, 1e6, O1);
    }

    function test_mandatesAreIsolatedPerOwner() public {
        address owner2 = makeAddr("owner2");
        token.mint(owner2, 50e6);
        vm.prank(owner2);
        token.approve(address(guard), type(uint256).max);
        vm.prank(agent);
        vm.expectRevert(AgentPayGuard.NoMandate.selector);
        guard.pay(owner2, shop, 1e6, O1);
    }

    function test_setMandateRejectsPastExpiry() public {
        vm.prank(owner);
        vm.expectRevert(AgentPayGuard.BadExpiry.selector);
        guard.setMandate(agent, 1e6, 1e6, uint64(block.timestamp));
    }

    function test_replacingMandateResetsSpendAndUnrevokes() public {
        vm.prank(agent);
        guard.pay(owner, shop, 30e6, O1);
        vm.startPrank(owner);
        guard.revoke(agent);
        guard.setMandate(agent, 50e6, 10e6, uint64(block.timestamp + 1 days));
        vm.stopPrank();
        assertEq(guard.remaining(owner, agent), 50e6);
        vm.prank(agent);
        guard.pay(owner, shop, 10e6, O2);
    }

    function testFuzz_neverExceedsBudgetOrCap(uint96 a1, uint96 a2) public {
        vm.startPrank(agent);
        uint256 total;
        for (uint256 i; i < 2; i++) {
            uint256 amt = i == 0 ? a1 : a2;
            try guard.pay(owner, shop, amt, keccak256(abi.encode(i))) {
                total += amt;
                assertLe(amt, 30e6);
            } catch {}
        }
        vm.stopPrank();
        assertLe(total, 100e6);
        assertEq(token.balanceOf(shop), total);
    }

    // ---- approval queue and daily limit ----

    function test_aboveThresholdWaitsForOwner() public {
        vm.prank(owner);
        guard.setApprovalThreshold(agent, 10e6);
        vm.prank(agent);
        guard.pay(owner, shop, 20e6, O1);
        assertEq(token.balanceOf(shop), 0, "nothing moves before approval");
        assertEq(guard.remaining(owner, agent), 100e6);
        vm.prank(owner);
        guard.approvePending(O1);
        assertEq(token.balanceOf(shop), 20e6);
        assertEq(guard.remaining(owner, agent), 80e6);
    }

    function test_belowThresholdPaysDirectly() public {
        vm.prank(owner);
        guard.setApprovalThreshold(agent, 10e6);
        vm.prank(agent);
        guard.pay(owner, shop, 10e6, O1);
        assertEq(token.balanceOf(shop), 10e6);
    }

    function test_agentCannotApproveItself() public {
        vm.prank(owner);
        guard.setApprovalThreshold(agent, 10e6);
        vm.startPrank(agent);
        guard.pay(owner, shop, 20e6, O1);
        vm.expectRevert(abi.encodeWithSelector(AgentPayGuard.NotPending.selector, O1));
        guard.approvePending(O1);
        vm.stopPrank();
        assertEq(token.balanceOf(shop), 0);
    }

    function test_rejectedPendingNeverPays() public {
        vm.prank(owner);
        guard.setApprovalThreshold(agent, 10e6);
        vm.prank(agent);
        guard.pay(owner, shop, 20e6, O1);
        vm.startPrank(owner);
        guard.rejectPending(O1);
        vm.expectRevert(abi.encodeWithSelector(AgentPayGuard.NotPending.selector, O1));
        guard.approvePending(O1);
        vm.stopPrank();
        assertEq(token.balanceOf(shop), 0);
    }

    function test_revokeAfterRequestBlocksApproval() public {
        vm.startPrank(owner);
        guard.setApprovalThreshold(agent, 10e6);
        vm.stopPrank();
        vm.prank(agent);
        guard.pay(owner, shop, 20e6, O1);
        vm.startPrank(owner);
        guard.revoke(agent);
        vm.expectRevert(AgentPayGuard.Revoked.selector);
        guard.approvePending(O1);
        vm.stopPrank();
    }

    function test_dailyLimitStopsDrainAndResetsAfterADay() public {
        vm.prank(owner);
        guard.setDailyLimit(agent, 25e6);
        vm.startPrank(agent);
        guard.pay(owner, shop, 20e6, O1);
        vm.expectRevert(abi.encodeWithSelector(AgentPayGuard.OverDailyLimit.selector, 10e6, 5e6));
        guard.pay(owner, shop, 10e6, O2);
        vm.warp(block.timestamp + 1 days + 1);
        vm.stopPrank();
        vm.prank(owner);
        guard.setMandate(agent, 100e6, 30e6, uint64(block.timestamp + 2 days));
        vm.prank(agent);
        guard.pay(owner, shop, 10e6, O2);
        assertEq(token.balanceOf(shop), 30e6);
    }
}
