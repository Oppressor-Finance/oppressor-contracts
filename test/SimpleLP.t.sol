// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {SimpleLP} from "../src/SimpleLP.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract SimpleLPTest is Test {
    SimpleLP public lp;
    MockERC20 public token;

    address public alice = address(1);
    address public bob = address(2);
    address public carol = address(3);

    function setUp() public {
        token = new MockERC20();
        lp = new SimpleLP(token);

        token.mint(alice, 1000 * 1e18);
        token.mint(bob, 1000 * 1e18);
        token.mint(carol, 1000 * 1e18);

        vm.startPrank(alice);
        token.approve(address(lp), 1000 * 1e18);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(lp), 1000 * 1e18);
        vm.stopPrank();
    }

    function testDeposit() public {
        vm.startPrank(alice);
        lp.deposit(100 * 1e18);

        assertEq(lp.totalShares(), 100 * 1e18);
        assertEq(lp.shares(alice), 100 * 1e18);
        assertEq(lp.totalTokens(), 100 * 1e18);

        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(alice);
        lp.deposit(100 * 1e18);
        lp.withdraw(50 * 1e18);

        assertEq(lp.totalShares(), 50 * 1e18);
        assertEq(lp.shares(alice), 50 * 1e18);
        assertEq(lp.totalTokens(), 50 * 1e18);
        assertEq(token.balanceOf(alice), 950 * 1e18);

        vm.stopPrank();
    }

    function testWithdrawWithoutEnoughShares() public {
        vm.startPrank(alice);
        lp.deposit(100 * 1e18);

        vm.expectRevert("Not enough shares");
        lp.withdraw(150 * 1e18);

        vm.stopPrank();
    }

    function testDirectTransferProfit() public {
        // Alice and Bob make initial deposits
        vm.startPrank(alice);
        lp.deposit(100 * 1e18);
        vm.stopPrank();

        vm.startPrank(bob);
        lp.deposit(100 * 1e18);
        vm.stopPrank();

        // Carol transfers tokens directly to the contract
        vm.startPrank(carol);
        token.transfer(address(lp), 100 * 1e18);
        vm.stopPrank();

        // Check balances and shares before withdrawals
        assertEq(lp.totalShares(), 200 * 1e18);
        assertEq(lp.shares(alice), 100 * 1e18);
        assertEq(lp.shares(bob), 100 * 1e18);
        assertEq(lp.totalTokens(), 300 * 1e18);

        // Alice and Bob withdraw their shares
        vm.startPrank(alice);
        lp.withdraw(100 * 1e18);
        vm.stopPrank();

        vm.startPrank(bob);
        lp.withdraw(100 * 1e18);
        vm.stopPrank();

        // Check final balances to ensure profits are distributed correctly
        assertEq(lp.totalShares(), 0);
        assertEq(lp.shares(alice), 0);
        assertEq(lp.shares(bob), 0);
        assertEq(lp.totalTokens(), 0);
        assertEq(token.balanceOf(alice), 1050 * 1e18); // Alice gets 50 tokens as profit
        assertEq(token.balanceOf(bob), 1050 * 1e18); // Bob gets 50 tokens as profit
    }

    function testMultipleDepositsWithdrawalsWithDirectTransfer() public {
        // Alice makes an initial deposit
        vm.startPrank(alice);
        lp.deposit(150 * 1e18);
        vm.stopPrank();

        // Bob makes an initial deposit
        vm.startPrank(bob);
        lp.deposit(250 * 1e18);
        vm.stopPrank();

        // Carol transfers tokens directly to the contract
        vm.startPrank(carol);
        token.transfer(address(lp), 400 * 1e18);
        vm.stopPrank();

        assertEq(lp.totalShares(), 400 * 1e18);
        assertEq(lp.shares(alice), 150 * 1e18);
        assertEq(lp.shares(bob), 250 * 1e18);
        assertEq(lp.shares(carol), 0 * 1e18);
        assertEq(token.balanceOf(alice), 850 * 1e18);
        assertEq(token.balanceOf(bob), 750 * 1e18);
        assertEq(lp.totalTokens(), 800 * 1e18);

        // Alice makes another deposit
        vm.startPrank(alice);
        lp.deposit(50 * 1e18);
        vm.stopPrank();

        assertEq(lp.totalShares(), (400 + 25) * 1e18);
        assertEq(lp.shares(alice), (150 + 25) * 1e18);
        assertEq(lp.shares(bob), 250 * 1e18);
        assertEq(token.balanceOf(alice), 800 * 1e18);
        assertEq(lp.totalTokens(), 850 * 1e18);

        // Alice withdraws 75 shares
        vm.startPrank(alice);
        lp.withdraw(75 * 1e18);
        vm.stopPrank();

        assertEq(lp.shares(alice), 100 * 1e18);
        assertEq(lp.shares(bob), 250 * 1e18);
        assertEq(lp.totalShares(), 350 * 1e18);
        assertEq(token.balanceOf(alice), (800 + 150) * 1e18);
        assertEq(token.balanceOf(bob), 750 * 1e18);
        assertEq(lp.totalTokens(), (850 - 150) * 1e18);

        // Alice withdraws 125 shares (half)
        vm.startPrank(bob);
        lp.withdraw(125 * 1e18);
        vm.stopPrank();

        assertEq(lp.shares(alice), 100 * 1e18);
        assertEq(lp.shares(bob), 125 * 1e18);
        assertEq(lp.totalShares(), 225 * 1e18);
        assertEq(token.balanceOf(alice), 950 * 1e18);
        assertEq(token.balanceOf(bob), (750 + 250) * 1e18);
        assertEq(lp.totalTokens(), (700 - 250) * 1e18);

        // Alice and Bob withdraw all remaining shares
        vm.startPrank(alice);
        lp.withdraw(100 * 1e18);
        vm.stopPrank();
        vm.startPrank(bob);
        lp.withdraw(125 * 1e18);
        vm.stopPrank();

        assertEq(lp.shares(alice), 0 * 1e18);
        assertEq(lp.shares(bob), 0 * 1e18);
        assertEq(lp.totalShares(), 0 * 1e18);
        assertEq(token.balanceOf(alice), (950 + 200) * 1e18);
        assertEq(token.balanceOf(bob), (1000 + 250) * 1e18);
        assertEq(lp.totalTokens(), 0 * 1e18);
    }
}
