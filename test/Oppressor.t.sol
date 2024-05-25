// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOppressor} from "../src/interfaces/IOppressor.sol";
import {Oppressor} from "../src/Oppressor.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockGovernor} from "../src/mocks/MockGovernor.sol";
import {SimpleLP} from "../src/SimpleLP.sol";
import {ILP} from "../src/interfaces/ILP.sol";

contract OppressorTest is Test {
    MockERC20 public token;
    MockGovernor public governor;
    SimpleLP public pool;
    Oppressor public oppressor;

    address public admin = address(this);
    address public alice = address(1);
    address public bob = address(2);
    address public carol = address(3);
    address public dave = address(4);

    function setUp() public {
        token = new MockERC20();
        pool = new SimpleLP(token);

        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        address[] memory executors = new address[](1);
        executors[0] = address(this);
        TimelockController timelock = new TimelockController(
            1 days,
            proposers,
            executors,
            admin
        );

        governor = new MockGovernor("Mock Governor", token, timelock);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), admin);

        oppressor = new Oppressor(ILP(address(pool)), governor);
        pool.setOppressor(oppressor);

        token.mint(admin, 10_000 * 1e18);
        token.mint(alice, 1000 * 1e18);
        token.mint(bob, 1000 * 1e18);
        token.mint(carol, 1000 * 1e18);
        token.mint(dave, 1000 * 1e18);

        vm.startPrank(admin);
        token.approve(address(oppressor), 10_000 * 1e18);
        token.approve(address(pool), 10_000 * 1e18);
        token.delegate(admin);
        vm.stopPrank();

        vm.startPrank(alice);
        token.approve(address(oppressor), 1000 * 1e18);
        token.delegate(alice);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(oppressor), 1000 * 1e18);
        token.delegate(bob);
        vm.stopPrank();

        vm.startPrank(carol);
        token.approve(address(oppressor), 1000 * 1e18);
        token.delegate(carol);
        vm.stopPrank();

        vm.startPrank(dave);
        token.approve(address(oppressor), 1000 * 1e18);
        token.delegate(dave);
        vm.stopPrank();
    }

    function testWithdrawFromPendingProposal() public {
        // Create a proposal
        address[] memory targets = new address[](1);
        targets[0] = address(token);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "mint(address,uint256)",
            dave,
            100 * 1e18
        );

        string memory description = "Mint 100 tokens to Dave";

        vm.startPrank(alice);
        uint256 proposalID = governor.propose(
            targets,
            values,
            calldatas,
            description
        );
        vm.stopPrank();

        vm.startPrank(alice);
        oppressor.bid(true, proposalID, 100 * 1e18); // Alice bids in yes
        vm.stopPrank();

        vm.startPrank(bob);
        oppressor.bid(false, proposalID, 200 * 1e18); // Bob bids no
        vm.stopPrank();

        // Alice withdraws her bid from the pending proposal
        vm.startPrank(alice);
        oppressor.withdrawFrom(proposalID);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 1000 * 1e18); // Alice should get her 100 tokens back
        (uint256 aliceYes, uint256 aliceNo) = oppressor.getVotesOf(
            alice,
            proposalID
        );
        // Alice's bid should be reset
        assertEq(
            keccak256(abi.encode(aliceYes, aliceNo)),
            keccak256(abi.encode(0, 0))
        );

        (uint256 no, uint256 yes, uint256 abstain) = governor.proposalVotes(
            proposalID
        );
        // Total yes votes should be reset
        assertEq(
            keccak256(abi.encode(no, yes, abstain)),
            keccak256(abi.encode(0, 0, 0))
        );
    }

    function testBidAndVoteProposalDefeated() public {
        assertEq(pool.totalTokens(), 0);
        assertEq(token.balanceOf(admin), 10_000 * 1e18);

        // Admin deposit 5000 token into the pool
        vm.startPrank(admin);
        pool.deposit(5000 * 1e18);
        vm.stopPrank();

        assertEq(pool.totalTokens(), 5000 * 1e18);
        assertEq(token.balanceOf(admin), 5000 * 1e18);

        // Create a proposal
        address[] memory targets = new address[](1);
        targets[0] = address(token);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "mint(address,uint256)",
            dave,
            100 * 1e18
        );

        string memory description = "Mint 100 tokens to Dave";

        vm.startPrank(alice);
        uint256 proposalID = governor.propose(
            targets,
            values,
            calldatas,
            description
        );
        vm.stopPrank();

        assertEq(
            governor.state(proposalID) == IGovernor.ProposalState.Pending,
            true
        );

        vm.startPrank(alice);
        oppressor.bid(true, proposalID, 100 * 1e18); // Alice bids in yes
        vm.stopPrank();

        vm.startPrank(bob);
        oppressor.bid(false, proposalID, 200 * 1e18); // Bob bids no
        vm.stopPrank();

        (bool IsVoteCast, uint256 yes, uint256 no) = oppressor.voteProposals(
            proposalID
        );
        assertEq(
            keccak256(abi.encode(IsVoteCast, yes, no)),
            keccak256(
                abi.encode(false, uint256(100 * 1e18), uint256(200 * 1e18))
            )
        );

        // Move forward in time to start voting
        vm.roll(block.number + governor.votingDelay() + 1);

        // Alice can't withdraw at this state
        vm.startPrank(alice);
        vm.expectRevert("Proposal is not pending");
        oppressor.withdrawFrom(proposalID);
        vm.expectRevert("Proposal is pending or active");
        oppressor.withdrawFailedBidsFrom(proposalID);
        vm.stopPrank();
        // Bob can't withdraw at this state
        vm.startPrank(bob);
        vm.expectRevert("Proposal is not pending");
        oppressor.withdrawFrom(proposalID);
        vm.expectRevert("Proposal is pending or active");
        oppressor.withdrawFailedBidsFrom(proposalID);
        vm.stopPrank();

        assertEq(pool.totalTokens(), (5000 + 0) * 1e18);

        // Dave casts the deciding vote
        vm.startPrank(dave);
        oppressor.vote(proposalID);
        vm.stopPrank();

        assertEq(pool.totalTokens(), (5000 + 200) * 1e18);

        vm.startPrank(carol);
        // Carol votes Support
        governor.castVote(proposalID, 1);
        vm.stopPrank();

        assertEq(
            governor.state(proposalID) == IGovernor.ProposalState.Active,
            true
        );

        uint256 abstain;
        (no, yes, abstain) = governor.proposalVotes(proposalID);
        assertEq(
            keccak256(abi.encode(no, yes, abstain)),
            keccak256(abi.encode(5000 * 1e18, 1000 * 1e18, 0))
        );

        // Move forward in time to end voting
        vm.roll(block.number + governor.votingPeriod() + 1);

        // Check that the correct vote was cast
        assertEq(
            governor.state(proposalID) == IGovernor.ProposalState.Defeated,
            true
        );

        assertEq(token.balanceOf(alice), (900) * 1e18);
        vm.startPrank(alice);
        // revert
        vm.expectRevert("Proposal is not pending");
        oppressor.withdrawFrom(proposalID);
        // not revert
        oppressor.withdrawFailedBidsFrom(proposalID);
        vm.stopPrank();
        // Alice gets the failed bids back
        assertEq(token.balanceOf(alice), (900 + 100) * 1e18);

        assertEq(token.balanceOf(bob), (800) * 1e18);
        vm.startPrank(bob);
        vm.expectRevert("Proposal is not pending");
        oppressor.withdrawFrom(proposalID);
        vm.expectRevert("'No' wins, then the sender's 'Yes' can't be zero");
        oppressor.withdrawFailedBidsFrom(proposalID);
        vm.stopPrank();
        // Bob belongs to the winning side and will not get anything back
        assertEq(token.balanceOf(bob), (800) * 1e18);

        // Admin withdraw all from the pool
        vm.startPrank(admin);
        pool.withdraw(pool.shares(admin));
        vm.stopPrank();

        // Admin should benefit from the protocol
        assertEq(token.balanceOf(admin), (10_000 + 200) * 1e18);
    }

    function testBidAndVoteProposalSucceeded() public {
        assertEq(pool.totalTokens(), 0);
        assertEq(token.balanceOf(admin), 10_000 * 1e18);

        // Admin deposit 5000 token into the pool
        vm.startPrank(admin);
        pool.deposit(5000 * 1e18);
        vm.stopPrank();

        assertEq(pool.totalTokens(), 5000 * 1e18);
        assertEq(token.balanceOf(admin), 5000 * 1e18);

        // Create a proposal
        address[] memory targets = new address[](3);
        targets[0] = address(token);
        targets[1] = address(token);
        targets[2] = address(token);

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        bytes[] memory calldatas = new bytes[](3);
        calldatas[0] = abi.encodeWithSignature(
            "mint(address,uint256)",
            alice,
            100 * 1e18
        );
        calldatas[1] = abi.encodeWithSignature(
            "mint(address,uint256)",
            carol,
            100 * 1e18
        );
        calldatas[2] = abi.encodeWithSignature(
            "mint(address,uint256)",
            dave,
            100 * 1e18
        );

        string
            memory description = "Alice, Carol, and Dave are teaming up against Bob";

        vm.startPrank(alice);
        uint256 proposalID = governor.propose(
            targets,
            values,
            calldatas,
            description
        );
        vm.stopPrank();

        vm.startPrank(alice);
        oppressor.bid(true, proposalID, 1000 * 1e18); // Alice bids in yes
        vm.stopPrank();

        vm.startPrank(bob);
        oppressor.bid(false, proposalID, 1000 * 1e18); // Bob bids no
        vm.stopPrank();

        vm.startPrank(carol);
        oppressor.bid(true, proposalID, 1000 * 1e18); // Carol bids in yes
        vm.stopPrank();

        vm.startPrank(dave);
        oppressor.bid(true, proposalID, 1000 * 1e18); // Dave bids in yes
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(carol), 0);
        assertEq(token.balanceOf(dave), 0);
        assertEq(token.balanceOf(address(oppressor)), 4000 * 1e18);
        assertEq(token.balanceOf(address(pool)), 5000 * 1e18);

        vm.roll(block.number + governor.votingDelay());

        // Alice betrays Carol and Dave in the last minute by withdrawing from Oppressor
        vm.startPrank(alice);
        oppressor.withdrawFrom(proposalID);
        vm.stopPrank();
        assertEq(token.balanceOf(address(oppressor)), 3000 * 1e18);
        assertEq(token.balanceOf(alice), 1000 * 1e18);

        // Move forward in time to start voting
        vm.roll(block.number + governor.votingDelay() + 1);

        // Carol notices Alice's actions and tries to follow, but it's too late now.
        vm.startPrank(carol);
        vm.expectRevert("Proposal is not pending");
        oppressor.withdrawFrom(proposalID);
        vm.stopPrank();
        assertEq(token.balanceOf(address(oppressor)), 3000 * 1e18);
        assertEq(token.balanceOf(carol), 0);

        // Check bidding results
        (bool IsVoteCast, uint256 yes, uint256 no) = oppressor.voteProposals(
            proposalID
        );
        assertEq(
            keccak256(abi.encode(IsVoteCast, yes, no)),
            keccak256(
                abi.encode(false, uint256(2000 * 1e18), uint256(1000 * 1e18))
            )
        );

        uint256 abstain;
        (no, yes, abstain) = governor.proposalVotes(proposalID);
        assertEq(
            keccak256(abi.encode(no, yes, abstain)),
            keccak256(abi.encode(0, 0, 0))
        );

        vm.startPrank(alice);
        governor.castVote(proposalID, 2);
        vm.stopPrank();

        (no, yes, abstain) = governor.proposalVotes(proposalID);
        assertEq(
            keccak256(abi.encode(no, yes, abstain)),
            keccak256(abi.encode(0, 0, 1000 * 1e18))
        );

        vm.startPrank(bob);
        governor.castVote(proposalID, 0);
        vm.stopPrank();

        (no, yes, abstain) = governor.proposalVotes(proposalID);
        assertEq(
            keccak256(abi.encode(no, yes, abstain)),
            keccak256(abi.encode(0, 0, 1000 * 1e18))
        );

        vm.startPrank(carol);
        governor.castVote(proposalID, 1);
        vm.stopPrank();

        (no, yes, abstain) = governor.proposalVotes(proposalID);
        assertEq(
            keccak256(abi.encode(no, yes, abstain)),
            keccak256(abi.encode(0, 0, 1000 * 1e18))
        );

        vm.startPrank(dave);
        governor.castVote(proposalID, 1);
        vm.stopPrank();

        (no, yes, abstain) = governor.proposalVotes(proposalID);
        assertEq(
            keccak256(abi.encode(no, yes, abstain)),
            keccak256(abi.encode(0, 0, 1000 * 1e18))
        );

        assertEq(token.balanceOf(address(oppressor)), 3000 * 1e18);
        assertEq(pool.totalTokens(), 5000 * 1e18);
        assertEq(pool.totalShares(), 5000 * 1e18);
        vm.startPrank(alice);
        oppressor.vote(proposalID);
        vm.stopPrank();
        (no, yes, abstain) = governor.proposalVotes(proposalID);
        assertEq(
            keccak256(abi.encode(no, yes, abstain)),
            keccak256(abi.encode(0, 5000 * 1e18, 1000 * 1e18))
        );
        assertEq(token.balanceOf(address(oppressor)), (3000 - 2000) * 1e18);
        assertEq(pool.totalTokens(), (5000 + 2000) * 1e18);
        assertEq(pool.totalShares(), 5000 * 1e18);

        // Nobody is able to withdraw anything now
        address[4] memory abcd = [alice, bob, carol, dave];
        for (uint256 i = 0; i < 4; i++) {
            vm.startPrank(abcd[i]);
            vm.expectRevert("Proposal is not pending");
            oppressor.withdrawFrom(proposalID);
            vm.expectRevert("Proposal is pending or active");
            oppressor.withdrawFailedBidsFrom(proposalID);
            vm.stopPrank();
        }

        // Move forward in time to end voting
        vm.roll(block.number + governor.votingPeriod() + 1);

        assertEq(token.balanceOf(address(oppressor)), 1000 * 1e18);
        for (uint256 i = 0; i < 4; i++) {
            if (abcd[i] == bob) {
                uint256 beforeBalance = token.balanceOf(abcd[i]);
                vm.startPrank(abcd[i]);
                // revert
                vm.expectRevert("Proposal is not pending");
                oppressor.withdrawFrom(proposalID);
                // not revert
                oppressor.withdrawFailedBidsFrom(proposalID);
                vm.stopPrank();
                assertEq(token.balanceOf(abcd[i]), beforeBalance + 1000 * 1e18);
            } else {
                uint256 beforeBalance = token.balanceOf(abcd[i]);
                vm.startPrank(abcd[i]);
                vm.expectRevert("Proposal is not pending");
                oppressor.withdrawFrom(proposalID);
                vm.expectRevert(
                    "'Yes' wins, then the sender's 'No' can't be zero"
                );
                oppressor.withdrawFailedBidsFrom(proposalID);
                vm.stopPrank();
                assertEq(token.balanceOf(abcd[i]), beforeBalance);
            }
        }
        assertEq(token.balanceOf(address(oppressor)), 0);
        assertEq(token.balanceOf(address(pool)), 7000 * 1e18);
        assertEq(token.balanceOf(alice), 1000 * 1e18);
        assertEq(token.balanceOf(bob), 1000 * 1e18);
        assertEq(token.balanceOf(carol), 0);
        assertEq(token.balanceOf(dave), 0);

        // Check that the correct vote was cast
        assertEq(
            governor.state(proposalID) == IGovernor.ProposalState.Succeeded,
            true
        );

        // Queue the proposal
        vm.startPrank(alice);
        governor.queue(
            targets,
            values,
            calldatas,
            keccak256(bytes(description))
        );
        vm.stopPrank();

        // Move forward in time to pass the timelock
        vm.warp(block.timestamp + 2 days);
        vm.startPrank(alice);
        governor.execute(
            targets,
            values,
            calldatas,
            keccak256(bytes(description))
        );
        vm.stopPrank();

        // Check balances again
        assertEq(token.balanceOf(address(oppressor)), 0);
        assertEq(token.balanceOf(address(pool)), 7000 * 1e18);
        assertEq(token.balanceOf(alice), (1000 + 100) * 1e18);
        assertEq(token.balanceOf(bob), (1000) * 1e18);
        assertEq(token.balanceOf(carol), (0 + 100) * 1e18);
        assertEq(token.balanceOf(dave), (0 + 100) * 1e18);

        // Admin withdraw all from the pool
        vm.startPrank(admin);
        pool.withdraw(pool.shares(admin));
        vm.stopPrank();

        // Admin should benefit from the protocol
        assertEq(token.balanceOf(admin), (10_000 + 2000) * 1e18);
    }
}
