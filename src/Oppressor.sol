// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOppressor} from "./interfaces/IOppressor.sol";
import {ILP} from "./interfaces/ILP.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Oppressor is IOppressor, ReentrancyGuard {
    ILP public pool;
    IGovernor public gov;

    mapping(uint256 => VoteProposal) public voteProposals;

    constructor(ILP pool_, IGovernor gov_) {
        require(address(pool_) != address(0), "Pool can't be address(0)");
        require(address(gov_) != address(0), "Governor can't be address(0)");

        pool = pool_;
        gov = gov_;
    }

    function deposit(uint256 amount) external {
        // TODO Is this still needed?
    }

    function getVotesOf(
        address voter,
        uint256 proposalID
    ) external view returns (uint256 yes, uint256 no) {
        VoteProposal storage vp = voteProposals[proposalID];
        yes = vp.yesVotes[voter];
        no = vp.noVotes[voter];
    }

    function withdrawFailedBidsFrom(uint256 proposalID) external {
        IGovernor.ProposalState state = gov.state(proposalID);
        require(
            state != IGovernor.ProposalState.Pending &&
                state != IGovernor.ProposalState.Active,
            "Proposal is pending or active"
        );
        VoteProposal storage vp = voteProposals[proposalID];
        uint256 senderYes = vp.yesVotes[msg.sender];
        uint256 senderNo = vp.noVotes[msg.sender];
        vp.yesVotes[msg.sender] = 0;
        vp.noVotes[msg.sender] = 0;
        if (vp.yes == vp.no) {
            require(
                senderYes + senderNo > 0,
                "Fail because sum of the votes is zero"
            );
            (pool.token()).transfer(msg.sender, senderYes + senderNo);
        } else if (vp.yes > vp.no) {
            require(
                senderNo > 0,
                "'Yes' wins, then the sender's 'No' can't be zero"
            );
            (pool.token()).transfer(msg.sender, senderNo);
        } else {
            require(
                senderYes > 0,
                "'No' wins, then the sender's 'Yes' can't be zero"
            );
            (pool.token()).transfer(msg.sender, senderYes);
        }
    }

    function withdrawFrom(uint256 proposalID) external nonReentrant {
        require(
            gov.state(proposalID) == IGovernor.ProposalState.Pending,
            "Proposal is not pending"
        );
        VoteProposal storage vp = voteProposals[proposalID];
        uint256 senderYes = vp.yesVotes[msg.sender];
        uint256 senderNo = vp.noVotes[msg.sender];
        vp.yesVotes[msg.sender] = 0;
        vp.noVotes[msg.sender] = 0;
        vp.yes -= senderYes;
        vp.no -= senderNo;
        require(senderYes + senderNo > 0, "Sum of the votes can't be zero");
        (pool.token()).transfer(msg.sender, senderYes + senderNo);
    }

    function bid(
        bool isSupport,
        uint256 proposalID,
        uint256 bidAmount
    ) external nonReentrant {
        require(
            gov.state(proposalID) == IGovernor.ProposalState.Pending,
            "Proposal is not pending"
        );
        VoteProposal storage vp = voteProposals[proposalID];
        if (isSupport) {
            vp.yes += bidAmount;
            vp.yesVotes[msg.sender] += bidAmount;
        } else {
            vp.no += bidAmount;
            vp.noVotes[msg.sender] += bidAmount;
        }
        (pool.token()).transferFrom(msg.sender, address(this), bidAmount);
    }

    function vote(uint256 proposalID) external nonReentrant {
        require(
            gov.state(proposalID) == IGovernor.ProposalState.Active,
            "Proposal is not active"
        );
        VoteProposal storage vp = voteProposals[proposalID];
        require(!vp.IsVoteCast, "Already cast a vote");
        require(vp.yes != vp.no, "Undecided");
        vp.IsVoteCast = true;
        (pool.token()).transfer(address(pool), vp.yes > vp.no ? vp.yes : vp.no);
        pool.castVote(vp.yes > vp.no ? uint8(1) : uint8(0), proposalID);
    }
}
