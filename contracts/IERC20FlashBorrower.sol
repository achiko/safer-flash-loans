pragma solidity 0.6.0;

interface IERC20FlashBorrower {
    function executeOnERC20FlashLoan(address token, uint256 amount, uint256 debt) external;
}
