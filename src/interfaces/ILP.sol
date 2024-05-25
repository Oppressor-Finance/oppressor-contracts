// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILP {
    function token() external view returns (IERC20);
    function deposit(uint256 amount) external;
    function withdraw(uint256 shareAmount) external;
    function castVote(uint8 isSupport, uint256 proposalID) external;
}
