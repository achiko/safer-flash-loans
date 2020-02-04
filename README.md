# easy-flash-loans

## Important!

Don't use these contracts. They have not been audited. I threw this idea together in a few hours and haven't even written tests for these. If you use them in production you are insane.

## What is this?

These are two contracts, [ERC20FlashLender](https://github.com/Austin-Williams/easy-flash-loans/blob/master/contracts/ERC20FlashLender.sol) and [ETHFlashLender](https://github.com/Austin-Williams/easy-flash-loans/blob/master/contracts/ETHFlashLender.sol), which can be inherited by any other contract to give the inheriting contract flash-loan capability _without having to give any consideration to the rest of your contract_.

The goal is for you to be able to this:

```
contract MyContract is ERC20FlashLender, ETHFlashLender { ... }

```
And then magically have safe flash-lending capability for your contract without having to worry about anything.

## How is this different from other flash loans?

With the usual flash-loan patterns you see in other projects, you very much DO have to be careful how the rest of your contract works. In particular, you need to lock down the all of the most interesting functionality with `nonReentrant` modifiers if you want to support flash loans (or else risk having your contract drained by attackers). For example, if you provide overcollateralized loans and also flash loans, your users will not be able to _use_ flash loans to liquidate overcollateralized loans that are in default -- because taking out the flash loan and then _reentering_ the contract to liquidate the defaulting loan would be blocked by your reentrancy gaurds.

The usual flash-loan pattern requires your users to take their borrowed money to some other project. But with the easy-flash-loans pattern presented here, your users can borrow money from your project _and use it to interact with your project_. This can be quite powerful for any project that requires arbitraguers in order for your mechanisms to behave properly (e.g.: most interesting DeFi projects).

### Explaination of the problem

Most other flash loans work like this (oversimplified example to get to the point):

```
contract Lender {
  // [...]
  
  flashLoan(uint256 amount) public nonReentrant {
    // record contract balance
    uint256 balanceBefore = address(this).balance;
    
    // send money to borrower
    msg.sender.transfer(amount);
    
    // hand control over to the borrower
    Borrower(msg.sender).execute();
    
    // calculate the interest the borrower has to pay
    uint256 interest = amount.add(amount.mul(interestRate).div(100));
    
    // verify that the loan has been paid back (this is the key)
    require(address(this) >= balanceBefore.add(interest), "loan not paid back")    
  }
  
  // [...]
}
```

And then, the Borrower's contract looks like this:

```
contract Borrower is Ownable {
// [...]

  // address of the Lender contract
  Lender public constant lender = Lender(0x123456);
  
  function borrow(uint256 amount) public onlyOwner {
    lender.flashLoan(amount);
  }
  
  function execute() public {
    require(msg.sender == lender, "only lender can call");
    
    // Do whatever you want with your borrowed money
    // ...
    
    // pay it back
    payable(address(lender)).transfer(amountowed);
  }
  
  // [...]
}
```

The key here is that the Lender contract checks whether or not the Borrower has paid back their loan _by checking the contract balance before and after the loan_. This is not ideal. It means that any user action that might change the contract balance (other than paying back the loan) must be restricted during the time the Borrower has the loan.

For example, suppose the above Lending contract had the following two functions that allow investors to add/remove money to the lending pool:

```
contract Lender {
  // [...]
  mapping(address => uint256) public balances;
  
  function deposit() public payable {
    balances[msg.sender] = balances[msg.sender].add(msg.value);
  }
  
   function withdraw(amount) public {
    balances[msg.sender] = balances[msg.sender].sub(amount);
    msg.sender.transfer(amount);
  }
  
  flashLoan(uint256 amount) public nonReentrant {
    // record contract balance
    uint256 balanceBefore = address(this).balance;
    
    // send money to borrower
    msg.sender.transfer(amount);
    
    // hand control over to the borrower
    Borrower(msg.sender).execute();
    
    // calculate the interest the borrower has to pay
    uint256 interest = amount.add(amount.mul(interestRate).div(100));
    
    // verify that the loan has been paid back (this is the key)
    require(address(this) >= balanceBefore.add(interest), "loan not paid back")    
  }
  
  // [...]
}
```

This is pretty basic functionality. But now an attacker can drain your contract. All the malicious Borrower has to do is call `flashLoan` with a `amount` equal to any amount up to the Lender's entire contract balance. Then in their `execute()` function, simple call the `deposit()` function on Lender, sending the entire amount owed.

The result is that the Lending contract has the balance it expects. It will think the loan has been paid back. But now the attacker has a balance in the `balances` mapping equal to the Lender's entire contract balance, and so can withdraw all the money from the contract via the `withdraw` function.

There are two solutions to this.

*Solution #1* (what most flash loan projects choose): lock down most/all functions in the Lender contract with a `nonReentrant` modifier. For example, the `deposit` function nwould have the `nonReentrant` modifier, so the above attack would not work.

This approach prevents all further meaningful interactions with the Lender contract while the Borrower has the loan.

*Solution #2* (what we're doing here): Check whether the Borrower has paid back the loan _without_ looking at the Lender contract's balance. This frees up users to be able to interact with your contract in all kinds of ways that might change the Lender contract's balance, without having to worry about it affecting the flash-loan accounting.

## How it works

Here is how it works (simplest example). This is simple instantiation of "Solution #2":

```
contract BetterLender {
  // [...]
  
  uint256 private _debt;
  
  flashLoan(uint256 amount) public {
    // calculate the interest the borrower has to pay
    uint256 interest = amount.add(amount.mul(interestRate).div(100));
    
    // record the incurred debt
    _debt = amount.add(interest);
    
    // send money to borrower
    msg.sender.transfer(amount);
    
    // hand control over to the borrower
    Borrower(msg.sender).execute();
    
    // verify that the loan has been paid back (this is the key)
    require(_debt == 0, "loan not repaid")
    
  }
  
  function repay() public payable {
    _debt = _debt.sub(msg.value);
  }
  
  // [...]
}
```
Notice that `address(this).balance` is never involed.

The Borrower contract is mostly unchanged. The only difference is that they must _explicitly_ repay the loan by calling BetterLender's `repay()` function.

And then, the Borrower's contract looks like this:

```
contract Borrower is Ownable {
// [...]

  // address of the Lender contract
  BetterLender public constant lender = BetterLender(0x123456);
  
  function borrow(uint256 amount) public onlyOwner {
    lender.flashLoan(amount);
  }
  
  function execute() public {
    require(msg.sender == lender, "only lender can call");
    
    // Do whatever you want with your borrowed money
    // ...
    
    // pay it back
    lender.repay(amountowed);
  }
  
  // [...]
}
```

That's it! The flash loan functionality doesn't even look any other part of the contract -- not even the contract balance. So there is no need to lock down the rest of your contract for the flash loan's sake.

# How to use the contracts

To add ERC20 flash loans to your contract, simply do:

```
contract MyContract is ERC20FlashLender {
  //...
}
```

This will add the ability for anyone to borrow _any_ ERC20 token that `MyContract` happens to hold. Borrowers can look at the [ERC20FlashBorrower](https://github.com/Austin-Williams/easy-flash-loans/blob/master/contracts/ERC20FlashBorrower.sol) contract to see how to perform flash borrows of ERC20 tokens. 

To add ETH flash loans to your contract, simply do:

```
contract MyContract is ETHFlashLender {
  //...
}
```

This will add the ability for anyone to borrow any/all ETH that `MyContract` happens to hold. Borrowers can look at the [ETHFlashBorrower](https://github.com/Austin-Williams/easy-flash-loans/blob/master/contracts/ETHFlashBorrower.sol) contract to see how to perform flash borrows of ETH. 


If you want to offer both  ERC20 _and_ ETH flash loans, then simply do:

```
contract MyContract is ERC20FlashLender, ETHFlashLender {
  //...
}
```

In all cases, is is critical that your `MyContract` MUST NOT shadow/overwrite any function or private variable in `ERC20FlashLender` or `ERC20FlashLender`.

# Security argument

The general security argument for why this approach to verifying flash loan repayment is safe:

- Before any flash loan, the `_debt` variable is 0.

- The only function that can increase the `_debt` variable is the `flashLoan` function. This sets the `_debt` variable to exactly the amount the borrower owes.

- The only function that can decrease the `_debt` variable is the `repay` function, which decreases the `_debt` variable by _exactly_ the amount of money that has been repaid via the `reapy` function.

- Therefore, if the loan has not been entirely repaid, then the `_debt` variable is greater than `0`.

- And if the `_debt` variable is `0`, then either the loan has been entirely repaid, or there was no loan to begin with.

# Bigger security considerations

Flash loans have the effect of temporarly decreasing your contract's balance (both ETH and ERC20 balances). If your contract relies on its ETH/ERC20 contract balances for business logic, then:

1. You should be very careful before deciding whether or not to use _any_ flash loans at all. These easy-flash-loans won't magically make your internal logic safe to use with flash loans generally.

2. You should carefully consider whether you can design away those direct balance-dependencies. See if you can perform the same logic without _ever_ invoking `address(this).balance` or `token.balanceOf(address(this))`.
