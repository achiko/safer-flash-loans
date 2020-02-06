pragma solidity 0.6.0;

interface IERC20FlashBorrower {
    function executeOnERC20FlashLoan(uint256 amount) external;
}
