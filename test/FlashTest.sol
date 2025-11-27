// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IFluidVaultResolver } from "fluid-contracts-public/contracts/periphery/resolvers/vault/iVaultResolver.sol";
import { Structs} from "fluid-contracts-public/contracts/periphery/resolvers/vault/structs.sol";
import { IFluidVault } from "fluid-contracts-public/contracts/protocols/vault/interfaces/iVault.sol";
interface IWETH is IERC20 {
    function deposit() external payable;
}

interface IFluidFlashLoan {
    function flashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256 route,
        bytes memory data,
        bytes memory extraData
    ) external;
}

interface IInstaFlashAggregator {
    function getRoutes() external pure returns (uint16[] memory routes);
}

interface IUniswapV3Router {
    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }
}


contract FlashLoanSwapReceiver {
    address constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant FLUID_VAULT_RESOLVER = 0x394Ce45678e0019c0045194a561E2bEd0FCc6Cf0; 

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata
    ) external returns (bool) {
        uint256 totalAmount = amounts[0] + premiums[0];
        IERC20(assets[0]).approve(UNISWAP_ROUTER, amounts[0]);
        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp + 300,
            amountIn: amounts[0],
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        IUniswapV3Router(UNISWAP_ROUTER).exactInputSingle(params);
        IERC20(assets[0]).transfer(msg.sender, totalAmount);
        return true;
    }

    function startFlashLoan(address router, address token, uint256 amount) external {
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        uint256[] memory amts = new uint256[](1);
        amts[0] = amount;
        uint16[] memory rutas = IInstaFlashAggregator(router).getRoutes();
        require(rutas.length > 0);
        uint route = rutas[0];
        IFluidFlashLoan(router).flashLoan(tokens, amts, route, "", "");
    }
}

contract FlashLoanSwapTest is Test {
    address constant FLUID_FLASH_LOAN_ROUTER = 0x619Ad2D02dBeE6ebA3CDbDA3F98430410e892882;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant FLUID_VAULT_RESOLVER = 0x394Ce45678e0019c0045194a561E2bEd0FCc6Cf0;

    FlashLoanSwapReceiver receiver;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        receiver = new FlashLoanSwapReceiver();
        deal(address(receiver), 100 ether);
        vm.startPrank(address(receiver));
        IWETH(WETH).deposit{value: 100 ether}();
        vm.stopPrank();
    }

    function testFlashLoanSwap() public {
        uint256 amount = 1 ether;
        uint balWETHBefore = IERC20(WETH).balanceOf(address(receiver));
        uint balUSDCBefore = IERC20(USDC).balanceOf(address(receiver));
        receiver.startFlashLoan(FLUID_FLASH_LOAN_ROUTER, WETH, amount);
        uint balWETHAfter = IERC20(WETH).balanceOf(address(receiver));
        uint balUSDCAfter = IERC20(USDC).balanceOf(address(receiver));
        console.log("WETH before:", balWETHBefore);
        console.log("WETH after :", balWETHAfter);
        console.log("USDC before:", balUSDCBefore);
        console.log("USDC after :", balUSDCAfter);
    }


   function testVaultResolver() public view {
    
    IFluidVaultResolver resolver = IFluidVaultResolver(FLUID_VAULT_RESOLVER);
    Structs.VaultEntireData memory data = resolver.getVaultEntireData(resolver.vaultByNftId(1));
    IFluidVault.ConstantViews memory constants = data.constantVariables;
    console.log("Vault Address:", resolver.vaultByNftId(1));
    console.log("Vault ID:", constants.vaultId);
    console.log("Vault Type:", constants.vaultType);
    console.log("Liquidity Address:", constants.liquidity);
    console.log("Factory Address:", constants.factory);
    console.log("Supply Token0:", constants.supplyToken.token0);
    console.log("Supply Token1:", constants.supplyToken.token1);
    console.log("Borrow Token0:", constants.borrowToken.token0);
    console.log("Borrow Token1:", constants.borrowToken.token1);
   }
    

}





