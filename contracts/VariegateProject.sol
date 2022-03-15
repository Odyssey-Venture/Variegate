// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "./Variegate.sol";
import "./RewardsTracker.sol";

contract VariegateProject is RewardsTracker {
  using SafeMath for uint256;
  using SafeMathInt for int256;

  struct Holder {
    uint256 index;
    uint256 share;
  }

  uint256 public holders = 0;
  mapping (uint256 => address) public holderAt;
  mapping (address => Holder) public holder;

  address[3] public admins;

  // uint256 public admins = 0;
  // mapping (uint256 => address) public officerAt;
  // mapping (address => Holder) public officer;

  uint256 public dividends = 10;
  uint256 public dividendsInBNB = 0;
  uint256 public funds = 0;

  uint256 public constant MIN_BALANCE = 250_000 ether; // TOKENS REQ FOR DIVIDENDS

  struct Confirm {
    uint256 expires;
    uint256 count;
    address[] accounts;
    bytes args;
  }

  mapping (bytes4 => Confirm) public confirm;

  event FundsApproved(address to, uint256 amount);
  event AdminChanged(address from, address to);
  event ConfirmationRequired(address account, bytes4 method, uint256 confirmations, uint256 required);
  event ConfirmationComplete(address account, bytes4 method, uint256 confirmations);

  constructor() RewardsTracker() {
   }

  modifier OnlyAdmin() {
    require(isAdmin(msg.sender), "Caller invalid");
    _;
  }

  function isAdmin(address account) public view returns (bool) {
    for (uint idx; idx<admins.length; idx++) if (admins[idx]==account) return true;
    return (admins.length==0 && account==owner()); // IF NO OFFICERS SET, CHECK OWNER
  }

  function confirmCall(uint256 required, address account, bytes4 method, bytes calldata args) public returns (bool) {
    require(isAdmin(account), "Caller invalid");

    if (required==1) return true;

    if (confirm[method].expires!=0 && (confirm[method].expires<block.timestamp || keccak256(confirm[method].args)!=keccak256(args))) { // EXISTING CALL EXPIRED OR ARGS NEQ
      delete confirm[method];
    }

    bool found = false;
    for (uint idx; idx<confirm[method].accounts.length; idx++) if (confirm[method].accounts[idx]==account) found = true; // CHECK RE-CONFIRMS

    if (!found) confirm[method].accounts.push(account);

    if (confirm[method].accounts.length==required) { // CONFIRMED
      emit ConfirmationComplete(account, method, required);
      delete confirm[method];
      return true;
    }

    confirm[method].count = confirm[method].accounts.length;
    confirm[method].args = args;
    confirm[method].expires = block.timestamp + 60 * 15;
    emit ConfirmationRequired(account, method, confirm[method].count, required);

    return false;
  }

  function getReport() public view returns (uint256 holderCount, uint256 totalDollars, uint256 totalDividends) {
    holderCount = holders;
    totalDollars = totalBalance;
    totalDividends = totalDistributed;
  }

  function getReportAccount(address key) public view returns (address account, uint256 index, uint256 shares, uint256 dividendsEarned, uint256 dividendsClaimed) {
    account = key;
    index = holder[account].index;
    shares = balanceOf[account];
    dividendsEarned = getAccumulated(account);
    dividendsClaimed = withdrawnRewards[account];
  }

  function getReportAccountAt(uint256 indexOf) public view returns (address account, uint256 index, uint256 shares, uint256 dividendsEarned, uint256 dividendsClaimed) {
    require(indexOf > 0 && indexOf <= holders, "Value invalid");

    return getReportAccount(holderAt[indexOf]);
  }

  function replaceAdmin(address from, address to) external OnlyAdmin {
    require(to!=address(0) && isAdmin(from) && !isAdmin(to), "Value invalid");

    if (!isConfirmed(2)) return;

    for (uint idx; idx<admins.length; idx++) if (admins[idx]==from) admins[idx] = to;
    emit AdminChanged(from, to);
  }

  function requestFunds(address to, uint256 amount) external OnlyAdmin {
    require(funds > amount, "Overdraft");

    if (!isConfirmed(2)) return;

    funds -= amount;
    (bool success,) = payable(to).call{ value: amount, gas: 3000 }("");
    if (success) {
      emit FundsApproved(to, amount);
    } else {
      funds += amount;
    }
  }

  function setHolders(address[] memory accounts, uint256[] memory dollars) external onlyOwner {
    require(totalBalance==0, "Shares already set.");
    require(accounts.length<100, "100 accounts max");

    for (uint256 idx=0;idx<accounts.length;idx++) {
      setHolder(accounts[idx], dollars[idx]);
    }

    dividendsInBNB = (totalBalance * 1 ether).div(333); // FOR EACH 1K DOLLARS RETURN 3 BNB TO INVESTORS - ADJUST TO CURRENT BNB PRICE AT LAUNCH
  }

  function setAdmins(address[] memory accounts) external onlyOwner {
    require(admins[0]==address(0), "Admins already set");
    require(accounts.length==3, "3 Admins required");

    for (uint256 idx=0;idx<accounts.length;idx++) admins[idx] = accounts[idx];
  }

  function withdrawFunds(address payable account) public override {
    require(getPending(account) > 0, "No funds");

    verifyMinimumBalance(account);
    super.withdrawFunds(account);
  }

  // PRIVATE

  function distributeFunds(uint256 amount) internal override {
    if (totalDistributed > dividendsInBNB) { // PAID IN FULL, NO MORE DISTRIBUTIONS
      funds += amount;
      return;
    }
    uint256 share = amount.mul(dividends).div(100);
    funds += amount.sub(share);
    super.distributeFunds(share);
  }

  function isConfirmed(uint256 required) private returns (bool) {
    return required < 2 || confirmCall(required, msg.sender, msg.sig, msg.data);
  }

  function setHolder(address account, uint256 dollars) internal {
    putBalance(account, dollars);
    if (holder[account].index==0) {
      holders++;
      holderAt[holders] = account;
      holder[account].index = holders;
    }
    holder[account].share = dollars;
  }

  function verifyMinimumBalance(address account) internal {
    if (owner().code.length==0) return;

    if (balanceOf[account] > 0 && Variegate(payable(owner())).balanceOf(account)<MIN_BALANCE) {
      putBalance(account, 0);
    } else if (balanceOf[account]==0 && Variegate(payable(owner())).balanceOf(account) >= MIN_BALANCE) {
      putBalance(account, holder[account].share);
    }
  }
}
