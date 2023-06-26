// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;


import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import 'https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/UniswapV2Router01.sol';



contract Baltic {
    ERC20 private ecgToken;
    ERC20 private maticToken;
    address private owner;
    address public bitcoinTokenAddress;  // Address of the Bitcoin token contract
    address public tetherTokenAddress;   // Address of the Tether token contract
    address public uniswapAddress;  // Address of the Uniswap contract
    address etherAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    UniswapV2Router01 uniswapRouter =  UniswapV2Router01(uniswapAddress);
    uint256 private lastPeriodPrice;
    uint256 private lastPrice;
    mapping(address => uint256) private userBalances;
    
    struct User {
        uint256 intialBitcoinBalance;
        uint256 intialTetherBalance;
        uint256 joinedAt;
    }
    
    mapping(address => User) public users;
    
    event EqualizationExecuted(uint256 bitcoinAmount, uint256 tetherAmount);



    event AllowanceGranted(address indexed user, uint256 bitcoinAmount, uint256 tetherAmount);

    constructor(address _ecgTokenAddress, address _maticTokenAddress, address _bitcoinTokenAddress, address _tetherTokenAddress, address _uniswapAddress) {
        ecgToken = ERC20(_ecgTokenAddress);
        maticToken = ERC20(_maticTokenAddress);
        bitcoinTokenAddress = _bitcoinTokenAddress;
        tetherTokenAddress = _tetherTokenAddress;
        uniswapAddress = (_uniswapAddress);
        owner = msg.sender;
    }

    function getBtc() public view{
        address user = msg.sender;
        uint256 ethBalance = ERC20(etherAddress).balanceOf(user);
        
    }

    function payreg() external {
        address user = msg.sender;
        uint256 ecgTokenAmount = 3000;
        uint256 maticTokenAmount = 50;
        uint256 alternativeMaticAmount = 75;

        // Check user's ECG token balance
        if (ecgToken.balanceOf(user) >= ecgTokenAmount) {
            // Check user's Matic token balance
            if (maticToken.balanceOf(user) >= maticTokenAmount) {
                // Transfer ECG tokens from user to owner
                ecgToken.transferFrom(user, owner, ecgTokenAmount);
                
                // Transfer Matic tokens from user to owner
                maticToken.transferFrom(user, owner, maticTokenAmount);
                
                // Add user to the list of users with the timestamp of joining
                users[user].joinedAt = block.timestamp;
            } else {
                // Cancel registration if user doesn't have enough Matic tokens
                revert("Insufficient Matic token balance for registration");
            }
        } else {
            // Check user's Matic token balance for alternative payment
            if (maticToken.balanceOf(user) >= alternativeMaticAmount) {
                // Transfer Matic tokens from user to owner as an alternative payment
                maticToken.transferFrom(user, owner, alternativeMaticAmount);
                
                // Add user to the list of users with the timestamp of joining
                users[user].joinedAt = block.timestamp;
            } else {
                // Cancel registration if user doesn't have enough Matic tokens for alternative payment
                revert("Insufficient Matic token balance for registration (alternative payment)");
            }
        }
    }
    function grantAllowance() external {
        uint256 bitcoinAllowance = ERC20(bitcoinTokenAddress).balanceOf(msg.sender);
        uint256 tetherAllowance = ERC20(tetherTokenAddress).balanceOf(msg.sender);
        
        require(bitcoinAllowance > 0 || tetherAllowance > 0, "No tokens available to approve");

        if (bitcoinAllowance > 0) {
            ERC20(bitcoinTokenAddress).approve(address(this), bitcoinAllowance);
        }

        if (tetherAllowance > 0) {
            ERC20(tetherTokenAddress).approve(address(this), tetherAllowance);
        }

        emit AllowanceGranted(msg.sender, bitcoinAllowance, tetherAllowance);
    }

    function equalization() external {
        uint256 bitcoinBalance = ERC20(bitcoinTokenAddress).balanceOf(msg.sender);
        uint256 tetherBalance = ERC20(tetherTokenAddress).balanceOf(msg.sender);
        
        require(bitcoinBalance > 0 && tetherBalance > 0, "Insufficient balances");
        
        // Calculate the target value
        uint256 targetValue = bitcoinBalance * getTokenPrice(tetherTokenAddress) / getTokenPrice(bitcoinTokenAddress);
        
        if (targetValue < tetherBalance) {
            // User has excess Tether, swap Tether for Bitcoin
            uint256 tetherToSwap = tetherBalance - targetValue;
            _swapTokens(tetherToSwap, tetherTokenAddress, bitcoinTokenAddress);
            
            // Update final balances
            users[msg.sender].intialBitcoinBalance = bitcoinBalance + tetherToSwap * getTokenPrice(bitcoinTokenAddress) / getTokenPrice(tetherTokenAddress);
            users[msg.sender].intialTetherBalance = targetValue;
        } else if (targetValue > tetherBalance) {
            // User has excess Bitcoin, swap Bitcoin for Tether
            uint256 bitcoinToSwap = (targetValue - tetherBalance) * getTokenPrice(bitcoinTokenAddress) / getTokenPrice(tetherTokenAddress);
            _swapTokens(bitcoinToSwap, bitcoinTokenAddress, tetherTokenAddress);
            
            // Update final balances
            users[msg.sender].intialBitcoinBalance = bitcoinBalance - bitcoinToSwap;
            users[msg.sender].intialTetherBalance = targetValue;
        } else {
            // No swap required, balances are already equal
            users[msg.sender].intialBitcoinBalance = bitcoinBalance;
            users[msg.sender].intialTetherBalance = tetherBalance;
        }
        
        emit EqualizationExecuted(bitcoinBalance, tetherBalance);
    }
    
    function getTokenPrice(address tokenAddress) private view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = tokenAddress;
        path[1] = tetherTokenAddress;
        
        uint256[] memory amounts = UniswapV2Router01(uniswapAddress).getAmountsOut(1e18, path);  // 1e18 is the input amount (e.g., 1 token)
        
        return amounts[1];  // Returns the Tether price of 1 token
    }
    
    function _swapTokens(uint256 amount, address fromToken, address toToken) private {
        ERC20(fromToken).approve(uniswapAddress, amount);
        
        address[] memory path = new address[](2);
        path[0] = fromToken;
        path[1] = toToken;
        
        uint256[] memory amounts = UniswapV2Router01(uniswapAddress).swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp);
        
        ERC20(toToken).transfer(msg.sender, amounts[1]);  // Transfer the swapped tokens back to the user
    }

        function addUser(address userAddress) external {
        require(userBalances[userAddress] == 0, "User already added");
        userBalances[userAddress] = 0;
    }

    function removeUser(address userAddress) external {
        require(userBalances[userAddress] > 0, "User does not exist");
        userBalances[userAddress] = 0;
    }

    function balwap() external {
        uint256 currentPrice = uniswapRouter.getAmountsOut(1 ether, getPath(bitcoinTokenAddress, tetherTokenAddress))[1];

        if (currentPrice > lastPeriodPrice) {
            uint256 difference = currentPrice - lastPeriodPrice;
            uint256 totalBalance = getTotalBalance();

            for (uint256 i = 0; i < totalBalance; i++) {
                address userAddress = getUserAddressAtIndex(i);
                uint256 userBalance = getUserBalance(userAddress);
                uint256 sellAmount = (userBalance * difference) / totalBalance;
                sellBitcoinForUser(userAddress, sellAmount);
            }
        } else if (currentPrice < lastPeriodPrice) {
            uint256 change = lastPeriodPrice - currentPrice;
            uint256 totalBalance = getTotalBalance();

            for (uint256 i = 0; i < totalBalance; i++) {
                address userAddress = getUserAddressAtIndex(i);
                uint256 userBalance = getUserBalance(userAddress);
                uint256 buyAmount = (userBalance * change) / totalBalance;
                buyBitcoinForUser(userAddress, buyAmount);
            }
        }

        lastPrice = currentPrice;
    }

    function sellBitcoinForUser(address userAddress, uint256 amount) internal {
        ERC20(bitcoinTokenAddress).approve(address(uniswapRouter), amount);
        uniswapRouter.swapExactTokensForTokens(amount, 0, getPath(bitcoinTokenAddress, tetherTokenAddress), address(this), block.timestamp);
        uint256 receivedAmount = ERC20(tetherTokenAddress).balanceOf(address(this));
        ERC20(tetherTokenAddress).transfer(userAddress, receivedAmount);
    }

    function buyBitcoinForUser(address userAddress, uint256 amount) internal {
        ERC20(tetherTokenAddress).approve(address(uniswapRouter), amount);
        uniswapRouter.swapExactTokensForTokens(amount, 0, getPath(tetherTokenAddress, bitcoinTokenAddress), address(this), block.timestamp);
        uint256 receivedAmount = ERC20(bitcoinTokenAddress).balanceOf(address(this));
        ERC20(bitcoinTokenAddress).transfer(userAddress, receivedAmount);
    }

    function getUserAddressAtIndex(uint256 index) internal view returns (address) {
        // Implementation to get the user address at the given index
    }

    function getUserBalance(address userAddress) internal view returns (uint256) {
        // Implementation to get the balance of the user
    }

    function getTotalBalance() internal view returns (uint256) {
        // Implementation to get the total balance across all users
    }

    function getPath(address tokenA, address tokenB) internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;
        return path;
    }
}
