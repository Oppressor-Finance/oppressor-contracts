// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

interface IOppressor {
    struct VoteProposal {
        bool IsVoteCast;
        uint256 yes;
        uint256 no;
        mapping(address => uint256) yesVotes;
        mapping(address => uint256) noVotes;
    }
    function gov() external view returns (IGovernor);
    function deposit(uint256 amount) external;
    function withdrawFrom(uint256 proposalID) external;
    function withdrawFailedBidsFrom(uint256 proposalID) external;
    function bid(
        bool isSupport,
        uint256 proposalID,
        uint256 bidAmount
    ) external;
    function vote(uint256 proposalID) external;
}
