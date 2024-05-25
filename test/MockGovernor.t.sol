// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockGovernor} from "../src/mocks/MockGovernor.sol";

contract MockGovernorTest is Test {
    MockERC20 public token;
    MockGovernor public governor;
    TimelockController public timelock;

    address public admin = address(this);
    address public alice = address(1);
    address public bob = address(2);
    address public carol = address(3);

    function setUp() public {
        token = new MockERC20();
        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        address[] memory executors = new address[](1);
        executors[0] = address(this);
        timelock = new TimelockController(1 days, proposers, executors, admin);

        governor = new MockGovernor("Mock Governor", token, timelock);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), admin);

        token.mint(alice, 1000 * 1e18);
        token.mint(bob, 2000 * 1e18);
        token.mint(carol, 500 * 1e18);

        vm.startPrank(alice);
        token.delegate(alice);
        vm.stopPrank();

        vm.startPrank(bob);
        token.delegate(bob);
        vm.stopPrank();

        vm.startPrank(carol);
        token.delegate(carol);
        vm.stopPrank();
    }

    function testProposeAndVote() public {
        // Create a proposal
        address[] memory targets = new address[](1);
        targets[0] = address(token);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "mint(address,uint256)",
            carol,
            100 * 1e18
        );

        string memory description = "Mint 100 tokens to Carol";

        vm.startPrank(alice);
        uint256 proposalID = governor.propose(
            targets,
            values,
            calldatas,
            description
        );
        vm.stopPrank();

        // Move forward in time to start voting
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.startPrank(alice);
        governor.castVote(proposalID, 1);
        vm.stopPrank();

        vm.startPrank(bob);
        governor.castVote(proposalID, 1);
        vm.stopPrank();

        (uint256 no, uint256 yes, uint256 abstain) = governor.proposalVotes(
            proposalID
        );
        assertEq(
            keccak256(abi.encode(no, yes, abstain)),
            keccak256(abi.encode(0, (1000 + 2000) * 1e18, 0))
        );

        // Move forward in time to end voting
        vm.roll(block.number + governor.votingPeriod() + 1);
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

        assertEq(token.balanceOf(carol), (500 + 100) * 1e18);
    }

    function testDominatingVoteAgainst() public {
        // Carol creates a proposal
        address[] memory targets = new address[](1);
        targets[0] = address(token);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "mint(address,uint256)",
            carol,
            100
        );

        string memory description = "Mint 100 tokens to Carol";

        vm.startPrank(carol);
        uint256 proposalID = governor.propose(
            targets,
            values,
            calldatas,
            description
        );
        vm.stopPrank();

        // Move forward in time to start voting
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.startPrank(alice);
        // Alice votes For
        governor.castVote(proposalID, 1);
        vm.stopPrank();

        vm.startPrank(bob);
        // Bob votes Against
        governor.castVote(proposalID, 0);
        vm.stopPrank();

        vm.startPrank(carol);
        // Carol votes For
        governor.castVote(proposalID, 1);
        vm.stopPrank();

        (uint256 no, uint256 yes, uint256 abstain) = governor.proposalVotes(
            proposalID
        );
        assertEq(
            keccak256(abi.encode(no, yes, abstain)),
            keccak256(abi.encode((2000) * 1e18, (1000 + 500) * 1e18, 0))
        );

        // Move forward in time to end voting
        vm.roll(block.number + governor.votingPeriod() + 1);

        assertEq(
            governor.state(proposalID) == IGovernor.ProposalState.Defeated,
            true
        );
    }

    function testDominatesVoteFor() public {
        // Alice creates a proposal
        address[] memory targets = new address[](1);
        targets[0] = address(token);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "mint(address,uint256)",
            carol,
            100 * 1e18
        );

        string memory description = "Mint 100 tokens to Carol";

        vm.startPrank(alice);
        uint256 proposalID = governor.propose(
            targets,
            values,
            calldatas,
            description
        );
        vm.stopPrank();

        // Move forward in time to start voting
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.startPrank(alice);
        // Alice votes For
        governor.castVote(proposalID, 1);
        vm.stopPrank();

        vm.startPrank(bob);
        // Bob votes For
        governor.castVote(proposalID, 1);
        vm.stopPrank();

        vm.startPrank(carol);
        // Carol votes Against
        governor.castVote(proposalID, 0);
        vm.stopPrank();

        (uint256 no, uint256 yes, uint256 abstain) = governor.proposalVotes(
            proposalID
        );
        assertEq(
            keccak256(abi.encode(no, yes, abstain)),
            keccak256(abi.encode((500) * 1e18, (1000 + 2000) * 1e18, 0))
        );

        // Move forward in time to end voting
        vm.roll(block.number + governor.votingPeriod() + 1);

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

        // Execute the proposal
        vm.warp(block.timestamp + 2 days); // Move forward in time to pass the timelock
        vm.startPrank(alice);
        governor.execute(
            targets,
            values,
            calldatas,
            keccak256(bytes(description))
        );
        vm.stopPrank();

        assertEq(token.balanceOf(carol), (500 + 100) * 1e18);
    }

    function testFailProposeWithoutQuorum() public {
        // Create a proposal
        address[] memory targets = new address[](1);
        targets[0] = address(token);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "mint(address,uint256)",
            carol,
            100 * 1e18
        );

        string memory description = "Mint 100 tokens to Carol";

        vm.startPrank(alice);
        uint256 proposalID = governor.propose(
            targets,
            values,
            calldatas,
            description
        );
        vm.stopPrank();

        // Move forward in time to start voting
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.startPrank(alice);
        governor.castVote(proposalID, 1);
        vm.stopPrank();

        // Move forward in time to end voting
        vm.roll(block.number + governor.votingPeriod() + 1);

        assertEq(
            governor.state(proposalID) == IGovernor.ProposalState.Defeated,
            true
        );
    }

    function testCancelProposal() public {
        // Create a proposal
        address[] memory targets = new address[](1);
        targets[0] = address(token);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "mint(address,uint256)",
            address(this),
            100 * 1e18
        );

        string memory description = "Mint 100 tokens to the test contract";

        vm.startPrank(alice);
        uint256 proposalID = governor.propose(
            targets,
            values,
            calldatas,
            description
        );
        vm.stopPrank();

        vm.roll(block.number + 1);
        assertEq(
            governor.state(proposalID) == IGovernor.ProposalState.Pending,
            true
        );

        // Cancel the proposal
        vm.startPrank(alice);
        governor.cancel(
            targets,
            values,
            calldatas,
            keccak256(bytes(description))
        );
        vm.stopPrank();

        assertEq(
            governor.state(proposalID) == IGovernor.ProposalState.Canceled,
            true
        );
    }
}
