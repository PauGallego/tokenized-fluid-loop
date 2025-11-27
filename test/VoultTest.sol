// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { LiquidityBaseTest} from "fluid-contracts-public/test/foundry/liquidity/liquidityBaseTest.t.sol";
import { IFluidLiquidityLogic } from "fluid-contracts-public/contracts/liquidity/interfaces/iLiquidity.sol";
import { FluidVaultT1 } from "fluid-contracts-public/contracts/protocols/vault/vaultT1/coreModule/main.sol";
import { FluidVaultT1Secondary } from "fluid-contracts-public/contracts/protocols/vault/vaultT1/coreModule/main2.sol";
import { FluidVaultT1Admin } from "fluid-contracts-public/contracts/protocols/vault/vaultT1/adminModule/main.sol";
import { MockOracle } from "fluid-contracts-public/contracts/mocks/mockOracle.sol";
import { FluidVaultFactory } from "fluid-contracts-public/contracts/protocols/vault/factory/main.sol";
import { FluidVaultT1DeploymentLogic } from "fluid-contracts-public/contracts/protocols/vault/factory/deploymentLogics/vaultT1Logic.sol";
import { MockonERC721Received } from "fluid-contracts-public/contracts/mocks/mockERC721.sol";
import { FluidVaultResolver } from "fluid-contracts-public/contracts/periphery/resolvers/vault/main.sol";
import { FluidLiquidityResolver } from "fluid-contracts-public/contracts/periphery/resolvers/liquidity/main.sol";
import { IFluidLiquidity } from "fluid-contracts-public/contracts/liquidity/interfaces/iLiquidity.sol";
import { Structs as AdminModuleStructs } from "fluid-contracts-public/contracts/liquidity/adminModule/structs.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


import "fluid-contracts-public/test/foundry/testERC20.sol";
import "fluid-contracts-public/test/foundry/testERC20Dec6.sol";
import "fluid-contracts-public/contracts/protocols/lending/lendingRewardsRateModel/main.sol";

abstract contract VaultFactoryBaseTest is LiquidityBaseTest {

    using SafeERC20 for IERC20; 
    using stdStorage for StdStorage;

    FluidVaultFactory vaultFactory;
    FluidVaultT1DeploymentLogic vaultT1Deployer;
    address vaultAdminImplementation_;
    address vaultSecondaryImplementation_;
    FluidLiquidityResolver liquidityResolver;
    FluidVaultResolver vaultResolver;

  

    function setUp() public virtual override {
        super.setUp();

        vaultFactory = new FluidVaultFactory(admin);
        vm.prank(admin);
        vaultFactory.setDeployer(alice, true);
        vaultAdminImplementation_ = address(new FluidVaultT1Admin());
        vaultSecondaryImplementation_ = address(new FluidVaultT1Secondary());
        vaultT1Deployer = new FluidVaultT1DeploymentLogic(
            address(liquidity),
            vaultAdminImplementation_,
            vaultSecondaryImplementation_
        );

        vm.prank(admin);
        vaultFactory.setGlobalAuth(alice, true);
        vm.prank(admin);
        vaultFactory.setVaultDeploymentLogic(address(vaultT1Deployer), true);

        liquidityResolver = new FluidLiquidityResolver(IFluidLiquidity(address(liquidity)));
        vaultResolver = new FluidVaultResolver(address(vaultFactory), address(liquidityResolver));


        //Add liquidity 
        TestERC20(address(USDC)).mint(address(liquidity), 1e40 ether);
        TestERC20(address(DAI)).mint(address(liquidity), 1e40 ether);
   

    }

    function _deployVault(uint64 nonce) internal returns (uint256) {
        vm.setNonceUnsafe(address(vaultFactory), nonce);
        stdstore.target(address(vaultFactory)).sig("totalVaults()").checked_write(nonce - 1);
        vm.startPrank(alice);
        nonce = vm.getNonce(address(vaultFactory));
        bytes memory vaultT1CreationCode = abi.encodeCall(vaultT1Deployer.vaultT1, (address(USDC), address(DAI)));
        address vault = vaultFactory.deployVault(address(vaultT1Deployer), vaultT1CreationCode);
        uint256 vaultId = FluidVaultT1(vault).VAULT_ID();
        address computedVaultAddress = vaultFactory.getVaultAddress(vaultId);
        vm.stopPrank();
        // console.log("Computed Vault Address for vaultId '%s' with nonce '%s': ", vaultId, nonce, computedVaultAddress);
        assertEq(vault, computedVaultAddress);
        return vaultId;
    }
   
}

contract VaultFactoryTest is VaultFactoryBaseTest {
    function testDeployNewVault() public {


        MockOracle oracle = new MockOracle();
    

        oracle.setPrice(1e18); // 1 USDC = 1 DAI

     
        vm.startPrank(alice);
        FluidVaultT1Admin vaultWithAdmin_;

        bytes memory vaultT1CreationCode = abi.encodeCall(vaultT1Deployer.vaultT1, (address(USDC), address(DAI)));
        address vault = vaultFactory.deployVault(address(vaultT1Deployer), vaultT1CreationCode);



        FluidVaultT1 vaultT1 = FluidVaultT1(address(vault));

        MockUser mockAlice = new MockUser(vaultT1, alice, USDC, DAI ); 


        // Updating admin related things to setup vault
        vaultWithAdmin_ = FluidVaultT1Admin(address(vault));
        vaultWithAdmin_.updateCoreSettings(
            10000, // supplyFactor_ => 100%
            10000, // borrowFactor_ => 100%
            8000, // collateralFactor_ => 80%
            9000, // liquidationThreshold_ => 90%
            9500, // liquidationMaxLimit_ => 95%
            500, // withdrawGap_ => 5%
            100, // liquidationPenalty_ => 1%
            100 // borrowFee_ => 1%
        );
        vaultWithAdmin_.updateOracle(address(oracle));

        vaultWithAdmin_.updateRebalancer(address(mockAlice));
        

        AdminModuleStructs.UserSupplyConfig[] memory supplyConfigs = new AdminModuleStructs.UserSupplyConfig[](1); 
        supplyConfigs[0] = AdminModuleStructs.UserSupplyConfig({
            user: address(vaultT1), 
            token: address(USDC),
            mode: 0,
            expandPercent: 10_000,
            expandDuration: block.timestamp + 1 days,
            baseWithdrawalLimit: type(uint256).max
        });


        changePrank(admin);

        IFluidLiquidity(address(liquidity)).updateUserSupplyConfigs(supplyConfigs);

        AdminModuleStructs.UserBorrowConfig[] memory borrowConfigs = new AdminModuleStructs.UserBorrowConfig[](1);
        borrowConfigs[0] = AdminModuleStructs.UserBorrowConfig({
            user: address(vaultT1),            
            token: address(DAI),             
            mode: 1,                            
            expandPercent: 10_000,            
            expandDuration: block.timestamp + 1 days,         
            baseDebtCeiling: 100_000e6,         
            maxDebtCeiling: 500_000e6           
        });


        IFluidLiquidity(address(liquidity)).updateUserBorrowConfigs(borrowConfigs);



        changePrank(alice);

        uint256 depositAmount = 10_000e10;

        USDC.transfer(address(mockAlice), depositAmount);

        console.log(USDC.balanceOf(address(mockAlice)));
        

        mockAlice.deposit(depositAmount);

    





    }
}

contract MockUser {
    FluidVaultT1 public vaultT1;
    address public alice;
    TestERC20Dec6 USDC;
    IERC20 DAI;

    constructor(FluidVaultT1 _vaultT1, address _alice, TestERC20Dec6 _USDC, IERC20 _DAI) {
        vaultT1 = _vaultT1;
        alice = _alice;
        USDC = _USDC;
        DAI = _DAI;
    }

    function deposit(uint256 depositAmount) external {

        uint vault_id;
        int new_col;
        int new_debt;

        USDC.approve(address(vaultT1), depositAmount);

        (vault_id, new_col, new_debt) = vaultT1.operate(
            0,
            int(depositAmount),
            10_000, 
            address(this)
        );
        

        console.log("NFT ID: ", vault_id);
        console.log("New Collateral: ", new_col);
        console.log("New Debt: ", new_debt);

        console.log(DAI.balanceOf(address(this)));





        

    }

    
}


