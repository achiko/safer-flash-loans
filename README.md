# easy-flash-loans

## Important!

Don't use these contracts. They have not been audited. I threw this idea together in a few hours and haven't even written tests for these. If you use them in production you are insane.

## What is this?

These are two contracts, [ERC20FlashLender](https://github.com/Austin-Williams/easy-flash-loans/blob/master/contracts/ERC20FlashLender.sol) and [ETHFlashLender](https://github.com/Austin-Williams/easy-flash-loans/blob/master/contracts/ETHFlashLender.sol), which can be inherited by any other contract to give the inheriting contract flash-loan capability _without having to to lock down the rest of your contract with nonReentrant modifiers_.

The goal is for you to be able to this:

```
contract MyContract is ERC20FlashLender, ETHFlashLender { ... }

```
And then magically have safe flash-lending capability for your contract without having to worry about anything (except for everything in the "Security Considerations" section at the bottom of this document).

## How is this different from other flash loans?

With the usual flash-loan patterns you see in other projects, you usually DO have to be careful to lock down the rest of your contract functionality with `nonReentrant` modifiers -- meaning your users have to _go away to some other Ethereum project_ to use the money they borrowed from you.

In particular, you need to lock down the all of the most interesting functionality with `nonReentrant` modifiers if you want to support flash loans (or else risk having your contract drained by attackers). For example, if you provide overcollateralized loans and flash loans via the same contract, your users will not be able to _use_ your flash loans to liquidate overcollateralized loans that are in default -- because taking out the flash loan and then _reentering_ the contract to liquidate the defaulting loan would be blocked by your reentrancy gaurds.

The usual flash-loan pattern requires your users to take their borrowed money to some other project. But with the easy-flash-loans pattern presented here, your users can borrow money from your project _and use it to interact with your project_. This can be quite powerful for any project that requires arbitraguers in order for your mechanisms to behave properly (e.g.: most interesting DeFi projects).

For example, it could allow arbitraguers to liquidate loans on your platform without requiring any up-front capital of their own and without having to go get a flash loan from some other project.

### Explaination of the problem

Most other flash loans work like this (oversimplified example to get to the point):

```
contract Lender is ReentrancyGuard {
  // ...
  
  flashLoan(uint256 amount) public nonReentrant {
    // record contract balance
    uint256 balanceBefore = address(this).balance;
    
    // send money to borrower
    msg.sender.transfer(amount);
    
    // hand control over to the borrower
    Borrower(msg.sender).execute();
    
    // calculate the interest the borrower has to pay
    uint256 interest = amount.mul(interestRate).div(100);
    
    // verify that the loan has been paid back (this is the key)
    require(address(this).balance >= balanceBefore.add(interest), "loan not paid back")    
  }
  
  // ...
}
```

And then, the Borrower's contract looks like this:

```
contract Borrower is Ownable {
  // ...

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
    payable(address(lender)).transfer(amountOwed);
  }
  
  // ...
}
```

The key here is that the Lender contract checks whether or not the Borrower has paid back their loan _by checking the contract balance before and after the loan_. This is not ideal. **It means that any user action that increases the contract balance is interpretted as the Borrower having paid back the loan.** But that's a very dangerous assumption.

For example, suppose the above Lending contract had the following two functions that allow investors to add/remove money to the lending pool:

```
contract Lender {
  // ...
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
    require(address(this).balance >= balanceBefore.add(interest), "loan not paid back")    
  }
  
  // ...
}
```

This is pretty basic functionality. But now an attacker can drain your contract. All the malicious Borrower has to do is call `flashLoan` with a `amount` equal to the Lender's entire contract balance. Then in their `execute()` function, simply call the `deposit()` function on Lender, sending the entire amount owed.

The result is that the Lending contract has the balance it expects. It will think the loan has been paid back. But now the attacker has a balance in the `balances` mapping equal to the Lender's entire contract balance, and so can withdraw all the money from the contract via the `withdraw` function.

This all stems from the fact that every increase of the contract balances is interpretted as the Borrower repaying a loan.

There are two solutions to this.

**Solution #1** (what most flash loan projects choose): lock down most/all functions in the Lender contract with a `nonReentrant` modifier. For example, the `deposit` function would have the `nonReentrant` modifier, so the above attack would not work.

This approach prevents all further meaningful interactions with the Lender contract while the Borrower has the loan. It is essentially _guaranteeing_ that all contract balance increases really _are_ due to the borrower paying back the loan, because no other interaction (e.g.: depositing money into the loan pool) is even possible.

**Solution #2** (what we're doing here): Check whether the Borrower has paid back the loan _without_ looking at the Lender contract's balance. This frees up users to be able to interact with your contract in all kinds of ways that might increase the Lender contract's balance, without us assuming those intereactions are loan repayments. We do this by restricting the Borrower so that they must use a _specific function_ on the Lender contract in order to pay back their loan. Only repayments via this special function are counted as the Borrower "paying back" their loan.

## How it works

Here is how it works (simplest example). This is a simple instantiation of "Solution #2":

```
contract BetterLender is ReentrancyGuard {
  // ...
  
  uint256 private _debt;
  
  flashLoan(uint256 amount) public nonReentrant {
    // calculate the interest the borrower has to pay
    uint256 interest = amount.mul(interestRate).div(100);
    
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
  
  // ...
}
```
Notice that `address(this).balance` is never involved.

The Borrower contract is mostly unchanged. The only difference is that they must _explicitly_ repay the loan by calling BetterLender's `repay()` function.

And then, the Borrower's contract looks like this:

```
contract Borrower is Ownable {
  // ...

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
    lender.repay(amountOwed);
  }
  
  // ...
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

In all cases, it is critical that your `MyContract` MUST NOT shadow/overwrite any function or private variable in `ERC20FlashLender` or `ERC20FlashLender`.

# Security argument

The general security argument for why this approach to verifying flash loan repayment is safe:

- Before any flash loan, the `_debt` variable is 0.

- The only function that can increase the `_debt` variable is the `flashLoan` function. This sets the `_debt` variable to exactly the amount the borrower owes.

- The only function that can decrease the `_debt` variable is the `repay` function, which decreases the `_debt` variable by _exactly_ the amount of money that has been repaid via the `repay` function.

- Therefore, if the loan has not been entirely repaid, then the `_debt` variable is greater than `0`.

- And if the `_debt` variable is `0`, then either the loan has been entirely repaid, or there was no loan to begin with.

# Security considerations

## For lenders

Flash loans have the effect of temporarly decreasing your contract's balance (both ETH and ERC20 balances). If your contract relies on its ETH/ERC20 contract balances for business logic, then:

1. You should be very careful before deciding whether or not to use _any_ flash loans at all. These easy-flash-loans won't magically make your internal logic safe to use with flash loans generally. While the loan is out and your contract balance(s) are low, any internal logic that relies on `address(this).balance` or `token.balanceOf(address(this))` may not act as intended.

2. You should carefully consider whether you can design away those direct balance-dependencies. See if you can perform the same logic without _ever_ invoking `address(this).balance` or `token.balanceOf(address(this))`. If you can, do it.

## For borrowers

A malicious flash lender could front-run your flash borrow with an agressive update to the borrower fee. For example, they could detect your borrow transaction, and then front-run with a fee update that is exactly of the right size to wipe out the entire ETH/token balance of your Borrower contract.

So if the project from which you are taking flash loans has the ability to instantly update the fee they charge, then it would be wise to implement a "fee check" in your Borrower contracts that reverts if the fee is larger than you expect.
