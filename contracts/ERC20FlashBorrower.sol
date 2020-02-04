pragma solidity 0.6.0;

import "./ERC20FlashLender.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/dev-v3.0/contracts/ownership/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/dev-v3.0/contracts/token/ERC20/IERC20.sol";

// @notice Used by borrower to flash-borrow ERC20 tokens from ERC20FlashLender
// @dev Example contract. Do not use. Has not been audited.
contract ERC20FlashBorrower is Ownable {
    
    IERC20 private _borrowedToken; // tracks token being borrowed
    
    // set the Lender contract address to a trusted ERC20FlashLender
    ERC20FlashLender public constant erc20FlashLender = ERC20FlashLender(address(0x0));

    // @notice Borrow any ERC20 token that the ERC20FlashLender holds
    function borrow(address token, uint256 amount) public onlyOwner {
        _borrowedToken = IERC20(token); // record which token was borrowed
        erc20FlashLender.ERC20FlashLoan(token, amount);
    }
    
    // this is called by ERC20FlashLender after borrower has received the tokens
    // every ERC20FlashBorrower must implement an `executeOnERC20FlashLoan()` function.
    function executeOnERC20FlashLoan() external {
        require(msg.sender == address(erc20FlashLender), "only lender can execute");
        
        //... do whatever you want with the tokens
        //...
        
        // repay loan
        uint256 debt = erc20FlashLender.tokenBorrowerDebt();
        _borrowedToken.approve(address(erc20FlashLender), debt);
        erc20FlashLender.repayERC20FlashLoan(debt);
        
        // recoup gas
        _borrowedToken = IERC20(address(0));
    }
}
