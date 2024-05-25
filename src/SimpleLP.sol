// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IOppressor} from "./interfaces/IOppressor.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";

contract SimpleLP is Ownable, ReentrancyGuard {
    IERC20 public token;
    IOppressor public oppressor;
    uint256 public totalShares;
    mapping(address => uint256) public shares;

    constructor(IERC20 token_) Ownable(msg.sender) {
        token = token_;
    }

    function setOppressor(IOppressor oppressor_) external onlyOwner {
        oppressor = oppressor_;
    }

    function totalTokens() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than zero");

        uint256 sharesToMint;
        sharesToMint = totalShares == 0
            ? amount
            : (amount * totalShares) / totalTokens();
        totalShares += sharesToMint;
        shares[msg.sender] += sharesToMint;

        // TODO should revisit how delegation actually works
        Votes(address(token)).delegate(address(this));
        token.transferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 shareAmount) external nonReentrant {
        require(shareAmount > 0, "Share amount must be greater than zero");
        require(shares[msg.sender] >= shareAmount, "Not enough shares");

        uint256 amountToWithdraw = (shareAmount * totalTokens()) / totalShares;

        totalShares -= shareAmount;
        shares[msg.sender] -= shareAmount;

        token.transfer(msg.sender, amountToWithdraw);
    }

    function castVote(
        uint8 isSupport,
        uint256 proposalID
    ) external nonReentrant {
        require(
            msg.sender == address(oppressor),
            "Sender is not the oppressor"
        );
        (oppressor.gov()).castVote(proposalID, isSupport);
    }
}
