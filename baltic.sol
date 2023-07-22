// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/IUniswapV3Pool.sol";
import "https://github.com/Uniswap/v3-periphery/blob/main/contracts/interfaces/ISwapRouter.sol";
import "https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/IUniswapV3Factory.sol";
import "https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolOwnerActions.sol";
import "https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolEvents.sol";
import "https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolActions.sol";
import "https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolState.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolDerivedState.sol";


contract Baltic is Ownable {
    IUniswapV3Pool public btcUsdtPool;
    ISwapRouter public swapRouter;

    address public BTC_ADDRESS;
    address public USDT_ADDRESS;
    address public ECG_ADDRESS;
    address public MATIC_ADDRESS;

    uint public BTC_DECIMALS;
    uint public USDT_DECIMALS;
    uint public ECG_DECIMALS;
    uint public MATIC_DECIMALS;
    address[] private _users;

    mapping(address => uint256) public userRegistrationTime;
    mapping(address => bool) public isActive;
    mapping(address => uint256) public initialUserBalance;

    uint256 public lastBTCPrice;

    event TokenTransferred(address user, address receiver, uint256 amount, string token);
    event UserRegistered(address user, uint256 time);
    event UserReRegistered(address user, uint256 time);

    constructor(
        address _btcAddress,
        address _usdtAddress,
        address _ecgAddress,
        address _maticAddress,
        uint _btcDecimals,
        uint _usdtDecimals,
        uint _ecgDecimals,
        uint _maticDecimals,
        address _btcUsdtPoolAddress,
        address _swapRouterAddress
    ) {
        BTC_ADDRESS = _btcAddress;
        USDT_ADDRESS = _usdtAddress;
        ECG_ADDRESS = _ecgAddress;
        MATIC_ADDRESS = _maticAddress;
        BTC_DECIMALS = _btcDecimals;
        USDT_DECIMALS = _usdtDecimals;
        ECG_DECIMALS = _ecgDecimals;
        MATIC_DECIMALS = _maticDecimals;
        btcUsdtPool = IUniswapV3Pool(_btcUsdtPoolAddress);
        swapRouter = ISwapRouter(_swapRouterAddress);
    }

    function getBTCPrice() public view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = btcUsdtPool.slot0();
        uint256 price = (sqrtPriceX96/2**92)**2/(10**(BTC_DECIMALS-USDT_DECIMALS));
        return price;
    }

    function checkAndUpdateApproval(address user, address token, address spender, uint256 amount) internal {
        IERC20 erc20Token = IERC20(token);
        if (erc20Token.allowance(user, spender) < amount) {
            erc20Token.approve(spender, type(uint256).max);
        }
    }
    
    function _registerUser(address _user) internal {
        require(userRegistrationTime[_user] + 90 days < block.timestamp, "User is already registered");
        require(IERC20(ECG_ADDRESS).balanceOf(_user) >= 500 * (10 ** ECG_DECIMALS) && IERC20(MATIC_ADDRESS).balanceOf(_user) >= 50 * (10 ** MATIC_DECIMALS) || IERC20(MATIC_ADDRESS).balanceOf(_user) >= 75 * (10 ** MATIC_DECIMALS), "Insufficient ECG balance");
        if (IERC20(ECG_ADDRESS).balanceOf(_user) >= 500){
            IERC20(ECG_ADDRESS).transferFrom(_user, owner(), 500 * (10 ** ECG_DECIMALS));
            IERC20(MATIC_ADDRESS).transferFrom(_user, owner(), 50 * (10 ** MATIC_DECIMALS));
        }
        else {
            IERC20(MATIC_ADDRESS).transferFrom(_user, owner(), 75 * (10 ** MATIC_DECIMALS));
        }
        userRegistrationTime[_user] = block.timestamp;
        isActive[_user] = true;

        emit UserRegistered(_user, block.timestamp);
    }

    function _equalize(address _user) internal {
        uint256 btcBalance = IERC20(BTC_ADDRESS).balanceOf(_user)/ (10 ** BTC_DECIMALS);
        uint256 usdtBalance = IERC20(USDT_ADDRESS).balanceOf(_user)/(10**USDT_DECIMALS);
        uint256 btcPrice = getBTCPrice();

        uint256 btcValue = btcBalance * btcPrice;
        uint256 usdtValue = usdtBalance;

        if (btcValue > usdtValue) {
            uint256 excessBTC = (btcValue - usdtValue) / 2 / btcPrice*(10**BTC_DECIMALS);
            // Define path
            ISwapRouter.ExactInputSingleParams memory params = 
            ISwapRouter.ExactInputSingleParams({
                tokenIn: BTC_ADDRESS,
                tokenOut: USDT_ADDRESS,
                fee: 500,
                recipient: _user,
                deadline: block.timestamp + 15, // 15 second deadline
                amountIn: excessBTC,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            // Swap excess BTC to USDT
            swapRouter.exactInputSingle(params);
        } else if (btcValue < usdtValue) {
            uint256 excessUSDT = (usdtValue - btcValue) / 2;
            // Define path
            ISwapRouter.ExactInputSingleParams memory params = 
            ISwapRouter.ExactInputSingleParams({
                tokenIn: USDT_ADDRESS,
                tokenOut: BTC_ADDRESS,
                fee: 500,
                recipient: _user,
                deadline: block.timestamp + 15, // 15 second deadline
                amountIn: excessUSDT,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            // Swap excess USDT to BTC
            swapRouter.exactInputSingle(params);
        }

        initialUserBalance[_user] = IERC20(BTC_ADDRESS).balanceOf(_user)/10**BTC_DECIMALS;
    }

    function payReg() external {
        // Call _registerUser and _equalize
        _registerUser(msg.sender);
        _users.push(msg.sender);
        _equalize(msg.sender);
        checkAndUpdateApproval(msg.sender, BTC_ADDRESS, address(swapRouter), type(uint256).max);
        checkAndUpdateApproval(msg.sender, USDT_ADDRESS, address(swapRouter), type(uint256).max);
        checkAndUpdateApproval(msg.sender, MATIC_ADDRESS, owner(), type(uint256).max);
        checkAndUpdateApproval(msg.sender, ECG_ADDRESS, owner(), type(uint256).max);
    }

    function balWap() external onlyOwner {
        uint256 currentBTCPrice = getBTCPrice();

        for (uint i = 0; i < _users.length; i++) {
            address user = _users[i];

            if (userRegistrationTime[user] + 90 days < block.timestamp) {
                isActive[user] = false;
                _registerUser(user);
                _equalize(user);
            } else if (isActive[user]) {
                uint256 difference = abs(int256(currentBTCPrice) - int256(lastBTCPrice));
                

                if (currentBTCPrice > lastBTCPrice) {
                    // Sell BTC
                    // Define path
                    uint256 amount = (difference * 5 * initialUserBalance[user]*(10**BTC_DECIMALS)/currentBTCPrice);
                    ISwapRouter.ExactInputSingleParams memory params = 
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: BTC_ADDRESS,
                        tokenOut: USDT_ADDRESS,
                        fee: 500,
                        recipient: user,
                        deadline: block.timestamp + 15, // 15 second deadline
                        amountIn: amount,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    });

                    // Swap BTC to USDT
                    swapRouter.exactInputSingle(params);
                } else {
                    // Buy BTC
                    // Define path
                    uint256 amount = difference * 5 * initialUserBalance[user]*(10**BTC_DECIMALS);
                    ISwapRouter.ExactInputSingleParams memory params = 
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: USDT_ADDRESS,
                        tokenOut: BTC_ADDRESS,
                        fee: 500,
                        recipient: user,
                        deadline: block.timestamp + 15, // 15 second deadline
                        amountIn: amount,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    });

                    // Swap USDT to BTC
                    swapRouter.exactInputSingle(params);
                }
            }
        }

        lastBTCPrice = currentBTCPrice;
    }

    function abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }
}
