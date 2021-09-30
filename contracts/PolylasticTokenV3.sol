/*
*
* Taxes structure:
*
* 3% taxes for Liquidity Pool
* 2% Burn wallet
* 1% Treasury wallet
* 3% RFI Static rewards to Holders
*
*/

pragma solidity >=0.6.0 <0.8.0;
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./math/SafeMath.sol";
import "./IERC20.sol";
// SPDX-License-Identifier: None

contract FanTest is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _isExcluded;
    address[] private _excluded;

    string private constant _name = "FanTest";
    string private constant _symbol = "FTEST";
    uint8 private constant _decimals = 9;

    uint256 private constant MAX = ~uint256(0);
    uint256 private constant _tTotal =  1 * 10**11 * 10**_decimals;

    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tRfiTotal;
    uint256 public numOfHODLers;
    uint256 private _tBurnTotal;
    uint256 private _tTreasuryTotal;

    //@dev enable optimisation to pack this in 32b
    struct feeRatesStruct {
      uint8 rfi;
      uint8 liquidity;
      uint8 Treasury;
      uint8 Burn;
    }

    feeRatesStruct public feeRates = feeRatesStruct(
     {rfi: 3,
      liquidity: 3,
      Treasury: 1,
      Burn: 2}); //32 bytes - perfect, as it should be

    struct valuesFromGetValues{
      uint256 rAmount;
      uint256 rTransferAmount;
      uint256 rRfi;
      uint256 tTransferAmount;
      uint256 tRfi;
      uint256 tLiquidity;
      uint256 tTreasury;
      uint256 tBurn;
    }

    address public TreasuryWallet;
    address public BurnWallet;

    IUniswapV2Router02 public immutable PancakeSwapV2Router;
    address public immutable pancakeswapV2Pair;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;

    uint256 public _maxTxAmount = 1 * 10**11 * 10**_decimals;
    uint256 public numTokensSellToAddToLiquidity = 1 * 10**7 * 10**_decimals;  //0.01%

    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 bnbReceidev, uint256 tokensIntoLiquidity);
    event BalanceWithdrawn(address withdrawer, uint256 amount);
    event LiquidityAdded(uint256 tokenAmount, uint256 bnbAmount);
    event MaxTxAmountChanged(uint256 oldValue, uint256 newValue);
    event SwapAndLiquifyStatus(string status);
    event WalletsChanged();
    event FeesChanged(uint8 _rfi, uint8 _lp, uint8 _Treasury, uint8 _Burn);
    event tokensBurned(uint256 amount, string message);


    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor () public {
        _rOwned[_msgSender()] = _rTotal;
        IUniswapV2Router02 _PancakeSwapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); //BSC Mainnet
        pancakeswapV2Pair = IUniswapV2Factory(_PancakeSwapV2Router.factory()).createPair(address(this), _PancakeSwapV2Router.WETH()); //only utility is to have the pair at hand, on bscscan...
        PancakeSwapV2Router = _PancakeSwapV2Router;

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    //std ERC20:
    function name() public pure returns (string memory) {
        return _name;
    }
    function symbol() public pure returns (string memory) {
        return _symbol;
    }
    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    //override ERC20:
    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }


    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tRfiTotal;
    }



    function reflectionFromToken(uint256 tAmount, bool deductTransferRfi) public view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferRfi) {
            valuesFromGetValues memory s = _getValues(tAmount, true);
            return s.rAmount;
        } else {
            valuesFromGetValues memory s = _getValues(tAmount, true);
            return s.rTransferAmount;
        }
    }


    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount.div(currentRate);
    }

    function excludeFromRFI(address account) public onlyOwner() {
        require(!_isExcluded[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeInRFI(address account) external onlyOwner() {
        require(_isExcluded[account], "Account is not excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function excludeFromFeeAndRfi(address account) public onlyOwner {
        excludeFromFee(account);
        excludeFromRFI(account);
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    /* @dev passing an array or just an uint256 would have been more efficient/elegant, I know
    */
    function setRfiRatesPercents(uint8 _rfi, uint8 _lp, uint8 _Treasury, uint8 _Burn) public onlyOwner {
      feeRates.rfi = _rfi;
      feeRates.liquidity = _lp;
      feeRates.Treasury = _Treasury;
      feeRates.Burn = _Burn;
      emit FeesChanged( _rfi, _lp, _Treasury, _Burn);
    }

    function setWallets(address _Treasury, address _Burn) public onlyOwner {
      TreasuryWallet = _Treasury;
      BurnWallet = _Burn;
      _isExcludedFromFee[_Treasury] = true;
      _isExcludedFromFee[_Burn] = true;
      emit WalletsChanged();
    }


   function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner {
       require(maxTxPercent <= 100, "maxTxPercent cannot exceed 100%");
        uint256 _previoiusAmount = _maxTxAmount;
        _maxTxAmount = _tTotal.mul(maxTxPercent).div(100);
        emit MaxTxAmountChanged(_previoiusAmount, _maxTxAmount);
    }

    function setMaxTxAmount(uint256 maxTxAmount) external onlyOwner {
        require(maxTxAmount <= _tTotal, "maxTxAmount cannot exceed total supply");
        uint256 _previoiusAmount=_maxTxAmount;
        _maxTxAmount = maxTxAmount;
        emit MaxTxAmountChanged(_previoiusAmount, _maxTxAmount);
    }

    //@dev swapLiq is triggered only when the contract's balance is above this threshold
    function setThreshholdForLP(uint256 threshold) external onlyOwner {
      numTokensSellToAddToLiquidity = threshold * 10**_decimals;
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    //  @dev receive BNB from pancakeswapV2Router when swapping
    receive() external payable {}

    function _reflectRfi(uint256 rRfi, uint256 tRfi) private {
        _rTotal = _rTotal.sub(rRfi);
        _tRfiTotal = _tRfiTotal.add(tRfi);
    }

    function _getValues(uint256 tAmount, bool takeFee) private view returns (valuesFromGetValues memory to_return) {
        to_return = _getTValues(tAmount, takeFee);
        (to_return.rAmount, to_return.rTransferAmount, to_return.rRfi) = _getRValues(to_return, tAmount, takeFee, _getRate());

        return to_return;

    }

    function _getTValues(uint256 tAmount, bool takeFee) private view returns (valuesFromGetValues memory s) {

        if(!takeFee) {
            s.tTransferAmount = tAmount;
            return s;
        }

        s.tRfi = tAmount.mul(feeRates.rfi).div(100);
        s.tLiquidity = tAmount.mul(feeRates.liquidity).div(100);
        s.tTreasury = tAmount.mul(feeRates.Treasury).div(100);
        s.tBurn = tAmount.mul(feeRates.Burn).div(100);

        s.tTransferAmount = tAmount.sub(s.tRfi).sub(s.tLiquidity).sub(s.tTreasury).sub(s.tBurn);

        return s;
    }

    function _getRValues(valuesFromGetValues memory s, uint256 tAmount, bool takeFee, uint256 currentRate) private pure returns (uint256 rAmount, uint256 rTransferAmount, uint256 rRfi) {

        rAmount = tAmount.mul(currentRate);
        if(!takeFee) {
          return(rAmount, rAmount, 0);
        }

        rRfi = s.tRfi.mul(currentRate);
        uint256 rLiquidity = s.tLiquidity.mul(currentRate);
        uint256 rTreasury = s.tTreasury.mul(currentRate);
        uint256 rBurn = s.tBurn.mul(currentRate);

        rTransferAmount = rAmount.sub(rRfi).sub(rLiquidity).sub(rTreasury).sub(rBurn);

        return (rAmount, rTransferAmount, rRfi);
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function _takeLiquidity(uint256 tLiquidity) private {
        uint256 currentRate =  _getRate();
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidity);
        if(_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidity);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(amount > 0, "Transfer amount must be greater than zero");
        require(amount <= balanceOf(from),"Insuf balance, check balance");

        if((from != owner() && to != owner()))
            require(amount <= _maxTxAmount, "Transfer amount exceeds the maxTxAmount.");

        uint256 contractTokenBalance = balanceOf(address(this));

        if(contractTokenBalance >= _maxTxAmount) {
            contractTokenBalance = _maxTxAmount;
        }

        bool overMinTokenBalance = contractTokenBalance >= numTokensSellToAddToLiquidity;
        if (overMinTokenBalance && !inSwapAndLiquify && from != pancakeswapV2Pair && swapAndLiquifyEnabled) {
            contractTokenBalance = numTokensSellToAddToLiquidity;
            //add liquidity
            swapAndLiquify(contractTokenBalance);
        }
        _tokenTransfer(from, to, amount, !(_isExcludedFromFee[from] || _isExcludedFromFee[to]));
    }


    function _tokenTransfer(address sender, address recipient, uint256 tAmount, bool takeFee) private {
        if (_rOwned[recipient] == 0) {numOfHODLers++;}
        valuesFromGetValues memory s = _getValues(tAmount, takeFee);

        if (_isExcluded[sender] && !_isExcluded[recipient]) {  //from excluded
                _tOwned[sender] = _tOwned[sender].sub(tAmount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) { //to excluded
                _tOwned[recipient] = _tOwned[recipient].add(s.tTransferAmount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) { //both excluded
                _tOwned[sender] = _tOwned[sender].sub(tAmount);
                _tOwned[recipient] = _tOwned[recipient].add(s.tTransferAmount);
        }

        //common to all transfers and == transfer std :
        _rOwned[sender] = _rOwned[sender].sub(s.rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(s.rTransferAmount);

        _takeLiquidity(s.tLiquidity);
        _reflectRfi(s.rRfi, s.tRfi);
        reflectBurnandTreasuryFee(s.tBurn,s.tTreasury);

        emit Transfer(sender, recipient, s.tTransferAmount);
    }

    function reflectBurnandTreasuryFee(uint256 tBurn, uint256 tTreasury) private {
        uint256 currentRate =  _getRate();
        uint256 rBurn =  tBurn.mul(currentRate);
        uint256 rTreasury =  tTreasury.mul(currentRate);
        _tBurnTotal = _tBurnTotal.add(tBurn);
        _rOwned[BurnWallet] = _rOwned[BurnWallet].add(rBurn);
        if(_isExcluded[BurnWallet])
            _tOwned[BurnWallet] = _tOwned[BurnWallet].add(tBurn);
        _tTreasuryTotal = _tTreasuryTotal.add(tTreasury);
        _rOwned[TreasuryWallet] = _rOwned[TreasuryWallet].add(rTreasury);
        if(_isExcluded[TreasuryWallet])
            _tOwned[TreasuryWallet] = _tOwned[TreasuryWallet].add(tTreasury);
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        // split the contract balance into halves
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        // capture the contract's current BNB balance.
        // this is so that we can capture exactly the amount of BNB that the
        // swap creates, and not make the liquidity event include any BNB that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        if(swapTokensForBNB(half)) { //enough liquidity ? If not, no swapLiq
          uint256 newBalance = address(this).balance.sub(initialBalance);
          addLiquidity(otherHalf, newBalance);
          emit SwapAndLiquify(half, newBalance, otherHalf);
        }
    }

    // @dev This is used by the swapAndLiquify function to swap to BNB
    // allowance optimisation, only when needed - max allowance since spender=uniswap
    function swapTokensForBNB(uint256 tokenAmount) private returns (bool status){

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = PancakeSwapV2Router.WETH();

        if(allowance(address(this), address(PancakeSwapV2Router)) < tokenAmount) {
          _approve(address(this), address(PancakeSwapV2Router), ~uint256(0));
        }

        try PancakeSwapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,0,path,address(this),block.timestamp) {
          emit SwapAndLiquifyStatus("Success");
          return true;
        }
        catch {
          emit SwapAndLiquifyStatus("Failed");
          return false;
        }

    }

    //add liquidity and get LP tokens to contract itself
    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        (uint256 tokenAmountAdded, uint256 bnbAmountAdded, )=PancakeSwapV2Router.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
        emit LiquidityAdded(tokenAmountAdded, bnbAmountAdded);
    }

    function withdrawStuckTokens(IERC20 token, address to) public onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        token.transfer(to, balance);
    }

    function withDrawLeftoverBNB(address payable receipient) public onlyOwner {
        receipient.transfer(address(this).balance);
    }

    function totalBurn() public view returns (uint256) {
        return _tBurnTotal;
    }
     function totalTreasuryFee() public view returns (uint256) {
        return _tTreasuryTotal;
    }

}
