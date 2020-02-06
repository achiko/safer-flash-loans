pragma solidity 0.6.0;

import "./ETHFlashLender.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/dev-v3.0/contracts/ownership/Ownable.sol";


// @notice Used by borrower to flash-borrow ETH from ETHFlashLender
// @dev Example contract. Do not use. Has not been audited.
contract ETHFlashBorrower is Ownable {

    // set the Lender contract address to a trusted ETHFlashLender
    ETHFlashLender public constant ethFlashLender = ETHFlashLender(address(0x0));

    // @notice Borrow any ETH that the ETHFlashLender holds
    function borrowETH(uint256 amount) public onlyOwner {
        ethFlashLender.ETHFlashLoan(amount);
    }
    
    // this is called by ETHFlashLender after borrower has received the ETH
    // every ETHFlashBorrower must implement an `executeOnETHFlashLoan()` function.
    function executeOnETHFlashLoan(uint256 amount) external {
        require(msg.sender == address(lender), "only lender can execute");
        
        //... do whatever you want with the ETH
        //...
        
        // repay loan
        ethFlashLender.repayEthDebt.value(ethFlashLender.ethBorrowerDebt());
    }
}
