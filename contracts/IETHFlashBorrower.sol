pragma solidity 0.6.0;

interface IETHFlashBorrower {
    function executeOnETHFlashLoan(uint256 amount) external;
}
