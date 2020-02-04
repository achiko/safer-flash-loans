pragma solidity 0.6.0;


import "./IERC20FlashBorrower.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/dev-v3.0/contracts/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/dev-v3.0/contracts/token/ERC20/IERC20.sol";





// @notice Any contract that inherits this contract becomes a flash lender of any/all ERC20 tokens that it holds
// @dev DO NOT USE. This is has not been audited.
contract ERC20FlashLender {
    using SafeMath for uint256;
    
    // private vars -- these should never be changed by inheriting contracts
    IERC20 private _borrowedToken; // holds the address of the token being borrowed
    uint256 private _tokenBorrowerDebt; // records how many tokens the borrower must repay
    
    // internal vars -- okay for inheriting contracts to change
    uint256 internal _tokenBorrowFee; // e.g.: 0.003e18 means 0.3% fee
    
    uint256 constant internal ONE = 1e18;

    // @notice Borrow tokens via a flash loan. See ERC20FlashBorrower for example.
    // @audit Necessarily violates checks-effects-interactions pattern.
    // @audit - is reentrancy okay here?
    // It would allow borrowing several different tokens in one txn.
    // Bit it is harder to reason about, so I'm leaning towards adding the nonReentrant modifier here.
    function ERC20FlashLoan(address token, uint256 amount) external {
        // set token
        _borrowedToken = IERC20(token); // used during repayment
        
        // record debt
        _tokenBorrowerDebt = amount.mul(ONE.add(_tokenBorrowFee)).div(ONE);
        
        // send borrower the tokens
        require(_borrowedToken.transfer(msg.sender, amount), "borrow failed");
        
        // hand over control to borrower
        IERC20FlashBorrower(msg.sender).executeOnERC20FlashLoan();
        
        // check that debt was fully repaid
        require(_tokenBorrowerDebt == 0, "loan not paid back");
        
        // set _token back to 0x0 to recoup gas
        _borrowedToken = IERC20(0);
    }
    
    // @notice Repay all or part of the loan
    function repayERC20FlashLoan(uint256 amount) public {
        _tokenBorrowerDebt = _tokenBorrowerDebt.sub(amount); // does not allow overpayment
        require(_borrowedToken.transferFrom(msg.sender, address(this), amount), "repay failed");
    }
    
    function borrowedToken() public view returns (address) {
        return address(_borrowedToken);
    }
    
    function tokenBorrowerDebt() public view returns (uint256) {
        return _tokenBorrowerDebt;
    }
    
    function tokenBorrowerFee() public view returns (uint256) {
        return _tokenBorrowFee;
    }
}
