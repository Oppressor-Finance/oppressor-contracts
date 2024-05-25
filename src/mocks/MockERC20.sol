// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract MockERC20 is ERC20Votes {
    constructor() ERC20("MockERC20", "M20") EIP712("MockERC20", "1") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
