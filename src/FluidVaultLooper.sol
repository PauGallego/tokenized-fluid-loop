// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;
import { IFluidVaultResolver } from "../imported/IVaultResolver.sol";
import { IFluidVault } from "../imported/IVault.sol";
import { ISwapRouter} from "lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol"; 
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Structs} from "../imported/structs.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { IFlashLoan } from "lib/flashloan-aggregator/contracts/misc/InstaReceiver.sol";
import { InstaFlashReceiverInterface } from "lib/flashloan-aggregator/contracts/aggregator/base/flashloan/interfaces.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
interface IInstaFlashAggregator {
    function getRoutes() external pure returns (uint16[] memory routes);
}

contract FluidVaultLooper is ERC4626, InstaFlashReceiverInterface, Ownable {

    event FlashLoanStarted(uint256 amount, uint16 route);
    event TokensSwapped(uint256 amountIn, uint256 amountOut);
    event VaultCreated(address vaultAddress);

    IFluidVaultResolver public immutable fluidVaultResolver;
    IFluidVault public immutable fluidVault;
    IFlashLoan public immutable fluidFlashLoanRouter;
    ISwapRouter public immutable uniswapRouter;
    IInstaFlashAggregator public immutable instaFlashAggregator;
    IERC20 public immutable dToken;
    uint8 public immutable leverage;

    constructor(
        address _flashLoanRouter,
        address _vaultResolver,
        address _uniswapRouter,
        address _instaFlashAggregator,
        address _asset,
        address _dToken,
        uint _fluidVaultId,
        uint8 _leverage,
        string memory _name,
        string memory _symbol
    )
        ERC20(_name, _symbol)
        ERC4626(IERC20(_asset))
        Ownable(msg.sender)
    {
        require(_flashLoanRouter != address(0), "Invalid flash loan router address");
        require(_vaultResolver != address(0), "Invalid vault resolver address");
        require(_uniswapRouter != address(0), "Invalid Uniswap router address");
        require(_instaFlashAggregator != address(0), "Invalid InstaFlash aggregator address");
        require(_dToken != address(0), "Invalid dToken address");
        require(_asset != address(0), "Invalid asset address");


        fluidFlashLoanRouter = IFlashLoan(_flashLoanRouter);
        fluidVaultResolver = IFluidVaultResolver(_vaultResolver);
        uniswapRouter = ISwapRouter(_uniswapRouter);
        instaFlashAggregator = IInstaFlashAggregator(_instaFlashAggregator);
        dToken = IERC20(_dToken);
        address vaultAddress = fluidVaultResolver.vaultByNftId(_fluidVaultId);
        fluidVault = IFluidVault(vaultAddress);
        leverage = _leverage;

        emit VaultCreated(vaultAddress);
    }


    function executeOperation( 
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata
    ) external returns (bool) {
        //Todo deposit into vault logic
    }

    function startFlashLoan(
        uint256 amount,
        uint16 route,
        bytes memory params,
        bytes memory userData
    ) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = address(dToken);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        fluidFlashLoanRouter.flashLoan(tokens, amounts, route, params, userData);
        emit FlashLoanStarted(amount, route);
    }

    function swapTokens(
        uint256 amountIn,
        uint24 fee,
        uint256 slippage
    ) internal returns (uint256 amountOut) {
        IERC20(address(dToken)).approve(address(uniswapRouter), amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(dToken),
            tokenOut: address(asset()),
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: amountIn,
            amountOutMinimum: amountIn * (10000 - slippage) / 10000,
            sqrtPriceLimitX96: 0
        });
        amountOut = uniswapRouter.exactInputSingle(params);
        emit TokensSwapped(amountIn, amountOut);
    }



}
