//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
//import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {console} from "forge-std/console.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address btcUsdPriceFeed;
    address wbtc;
    uint256 deployerKey;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether; // 10 ETH

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE); // Mint 10 ETH to USER
    }

    // Constructor tests //

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18; // 15 ETH
        uint256 expectedUsd = 30000e18; // Assuming ETH price is $2000
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd, "USD value calculation is incorrect");
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 30000e18; // $30,000
        uint256 expectedEthAmount = 15e18; // Assuming ETH price is $2000
        uint256 actualEthAmount = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualEthAmount, expectedEthAmount, "Token amount from USD calculation is incorrect");
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0); // Attempt to deposit zero collateral
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("Random Token", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine_NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL); // Attempt to deposit collateral that is not approved
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInformation() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0; // Initially, no DSC is minted
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted, "Total DSC minted should be zero initially");
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount, "Collateral value in USD should match the deposited amount");
    }

    function testCanDepositCollateralAndMintDsc() public {
        uint256 mintAmount = 5 ether;

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, mintAmount);
        vm.stopPrank();

        // Check the DSC balance
        uint256 userDscBalance = dsc.balanceOf(USER);
        assertEq(userDscBalance, mintAmount);

        // Check internal accounting
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, mintAmount);
        assertGt(collateralValueInUsd, 0);
    }

    function testRevertsWhenNotApproved() public {
        uint256 mintAmount = 5 ether;

        vm.startPrank(USER);
        // Not approving the token
        vm.expectRevert(); // You can specify the expected error if known
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, mintAmount);
        vm.stopPrank();
    }

    function testRevertsWhenCollateralZeroAndMintZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), 0);
        vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        dsce.depositCollateralAndMintDsc(weth, 0, 0);
        vm.stopPrank();
    }

    //     function testCanDepositCollateralSuccessfully() public {
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

    //     vm.expectEmit(true, true, true, true);
    //     emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL); // ✅ NO DSCEngine. prefix

    //     dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    //     vm.stopPrank();

    //     uint256 deposited = dsce.getCollateralBalanceOfUser(USER, weth);
    //     assertEq(deposited, AMOUNT_COLLATERAL);
    // }

    function testRevertsIfCollateralAmountIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), 0);

        vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsIfCollateralTokenIsNotAllowed() public {
        ERC20Mock ranToken = new ERC20Mock("Random", "RDM", USER, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        ranToken.approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine_NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // function testRevertsIfTransferFails() public {
    //     ERC20Mock badToken = new ERC20Mock("BadToken", "BAD", address(this), 0); // no balance

    //     // Add to allowed tokens (if your contract supports it)
    //     vm.prank(USER); // impersonate owner if needed
    //     dsce.addAllowedToken(address(badToken));

    //     vm.startPrank(USER);
    //     badToken.approve(address(dsce), AMOUNT_COLLATERAL);

    //     vm.expectRevert(DSCEngine.DSCEngine_TransferFailed.selector);
    //     dsce.depositCollateral(address(badToken), AMOUNT_COLLATERAL);
    //     vm.stopPrank();
    // }

    function testMultipleDepositsAccumulate() public {
        uint256 deposit1 = 2 ether;
        uint256 deposit2 = 3 ether;

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), deposit1 + deposit2);
        dsce.depositCollateral(weth, deposit1);
        dsce.depositCollateral(weth, deposit2);
        vm.stopPrank();

        uint256 total = dsce.getCollateralBalanceOfUser(USER, weth); // Or access mapping if public
        assertEq(total, deposit1 + deposit2);
    }

    function testRedeemCollateralSuccess() public {
        uint256 mintAmount = 100e18;
        uint256 depositAmount = 200e18;
        deal(address(weth), USER, depositAmount);

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), depositAmount);
        dsce.depositCollateralAndMintDsc(weth, depositAmount, mintAmount);

        dsc.approve(address(dsce), mintAmount); // <- Fixed this line
        dsce.redeemCollateralForDsc(weth, 50e18, 50e18);
        vm.stopPrank();

        uint256 userWethBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(userWethBalance, 50e18);
    }

    function testRedeemFailsIfNotEnoughDsc() public {
        uint256 depositAmount = 100e18;
        deal(address(weth), USER, depositAmount);

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), depositAmount);
        dsce.depositCollateral(weth, depositAmount);

        vm.expectRevert(); // Depends on how burnDsc handles insufficient balance
        dsce.redeemCollateralForDsc(weth, 10e18, 10e18);
        vm.stopPrank();
    }

    function testRedeemFailsIfCollateralTooHigh() public {
        uint256 depositAmount = 50e18;
        uint256 mintAmount = 30e18;

        deal(address(weth), USER, depositAmount);

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), depositAmount);
        dsce.depositCollateralAndMintDsc(weth, depositAmount, mintAmount);

        dsc.approve(address(dsce), mintAmount); // ✅ FIXED here

        vm.expectRevert(); // This should match your revert message if specific
        dsce.redeemCollateralForDsc(weth, 60e18, 30e18);
        vm.stopPrank();
    }

    function testRedeemCollateralWorks() public {
        uint256 deposit = 10 ether;
        uint256 mintAmount = 5 ether;
        uint256 redeemAmount = 2 ether;

        // Give USER WETH
        deal(address(weth), USER, deposit);

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), deposit);

        // Step 1: Deposit collateral and mint DSC
        dsce.depositCollateralAndMintDsc(address(weth), deposit, mintAmount);

        // Step 2: Approve DSC for redemption
        dsc.approve(address(dsce), redeemAmount);

        // Step 3: Redeem collateral
        dsce.redeemCollateralForDsc(address(weth), redeemAmount, redeemAmount);

        vm.stopPrank();

        // Step 4: Assert
        uint256 remaining = dsce.getCollateralBalanceOfUser(USER, address(weth));
        assertEq(remaining, deposit - redeemAmount);
    }

    function testRedeemZeroReverts() public {
        vm.startPrank(USER);
        vm.expectRevert(); // or expectRevert(DSCEngine__MustBeMoreThanZero.selector);
        dsce.redeemCollateral(address(weth), 0);
        vm.stopPrank();
    }

    function testRedeemMoreThanDepositedReverts() public {
        uint256 deposit = 2 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), deposit);
        dsce.depositCollateral(address(weth), deposit);

        // Attempt to redeem more than deposited
        vm.expectRevert();
        dsce.redeemCollateral(address(weth), deposit + 1 ether);
        vm.stopPrank();
    }

    function testRedeemBreaksHealthFactorReverts() public {
        uint256 deposit = 10 ether;
        uint256 mint = 5 ether;

        // User deposits and mints
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), deposit);
        dsce.depositCollateral(address(weth), deposit);
        dsce.mintDsc(mint);

        // Trying to redeem too much will break health factor
        vm.expectRevert();
        dsce.redeemCollateral(address(weth), deposit);
        vm.stopPrank();
    }

    function testMintDscWorks() public {
        uint256 deposit = 10 ether;
        uint256 mintAmount = 5 ether;

        // Give USER WETH
        deal(address(weth), USER, deposit);

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), deposit);

        // Step 1: Deposit collateral
        dsce.depositCollateral(address(weth), deposit);

        // Step 2: Mint DSC
        dsce.mintDsc(mintAmount);

        vm.stopPrank();

        // Step 3: Assert
        uint256 userDscBalance = dsc.balanceOf(USER);
        assertEq(userDscBalance, mintAmount);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, mintAmount, "Total DSC minted should match mintAmount");
        assertGt(collateralValueInUsd, 0, "Collateral value in USD should be greater than zero");
    }

    // function testMintDsc() public {
    //     uint256 mintAmount = 100e18;

    //     // Arrange
    //     deal(address(weth), USER, mintAmount);
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), mintAmount);
    //     dsce.depositCollateral(address(weth), mintAmount); // Ensure health factor > 1

    //     // Act
    //     dsce.mintDsc(mintAmount);

    //     // Assert
    //     uint256 userMinted = dsce.getDscMinted(USER);
    //     assertEq(userMinted, mintAmount);

    //     vm.stopPrank();
    // }

    // function testMintDscRevertsIfMintFails() public {
    //     uint256 mintAmount = 100e18;

    //     // Arrange
    //     deal(address(weth), USER, mintAmount);
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), mintAmount);
    //     dsce.depositCollateral(address(weth), mintAmount); // ensure user has some collateral

    //     // Act & Assert
    //     vm.expectRevert(DSCEngine.DSCEngine_BreaksHealthFactor.selector); // <- this is the actual error defined in your contract
    //     dsce.mintDsc(mintAmount + 1 ether); // trying to mint more than allowed
    //     vm.stopPrank();
    // }

    // function testMintDscRevertsIfHealthFactorTooLow() public {
    //     uint256 collateralAmount = 1 ether;
    //     uint256 mintAmount = 2000e18 + 1e18; // Try to mint more than allowed (assuming WETH price = $2000)

    //     // Arrange
    //     deal(address(weth), USER, collateralAmount);
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), collateralAmount);
    //     dsce.depositCollateral(address(weth), collateralAmount); // ~$2000 in USD value

    //     // Act & Assert
    //     vm.expectRevert(DSCEngine.DSCEngine__HealthFactorTooLow.selector);
    //     dsce.mintDsc(mintAmount); // Trying to mint more than worth of collateral
    //     vm.stopPrank();
    // }

    //    function testBurnDscReducesBalance() public {
    //     uint256 collateralAmount = 100 ether;
    //     uint256 mintAmount = 100 ether;

    //     vm.startPrank(USER);

    //     // Setup: mint and approve collateral (e.g., WETH)
    //     weth.mint(USER, collateralAmount);
    //     weth.approve(address(dsce), collateralAmount);

    //     // Step 1: Deposit collateral
    //     dsce.depositCollateral(address(weth), collateralAmount);

    //     // Step 2: Mint DSC against the collateral
    //     dsce.mintDsc(mintAmount);

    //     // Step 3: Burn part of the DSC
    //     dsce.burnDsc(50 ether);

    //     vm.stopPrank();

    //     // Step 4: Assert balance reduced
    //     uint256 remainingDsc = dsce.getDscMinted(USER); // Ensure this getter exists and is public
    //     assertEq(remainingDsc, 50 ether);
    // }

    function testBurnDsc() public {
        uint256 mintAmount = 100e18;

        // Arrange
        deal(address(weth), USER, mintAmount);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), mintAmount);
        dsce.depositCollateral(address(weth), mintAmount); // Ensure health factor > 1

        dsce.mintDsc(mintAmount);

        // ✅ Add this approve for burning
        dsc.approve(address(dsce), mintAmount / 2);

        // Act
        dsce.burnDsc(mintAmount / 2);

        // Assert
        uint256 userMinted = dsce.getDscMinted(USER);
        assertEq(userMinted, mintAmount / 2);

        vm.stopPrank();
    }

    // function testBurnDscRevertsIfBurnFails() public {
    //     uint256 mintAmount = 100e18;

    //     // Arrange
    //     deal(address(weth), USER, mintAmount);
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), mintAmount);
    //     dsce.depositCollateral(address(weth), mintAmount);

    //     // Mint some DSC
    //     dsce.mintDsc(mintAmount);

    //     // Try burning more than owned
    //     vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine_BurnFailed.selector));
    //     dsce.burnDsc(mintAmount + 1 ether); // Intentionally more than minted
    //     vm.stopPrank();
    // }

    // function testHealthFactorSafeAfterBurn() public {
    //     // Arrange
    //     uint256 collateralAmount = 1000e18; // assume ETH/USD = $1000, so this is $1,000,000
    //     uint256 mintAmount = 100e18; // mint 100 DSC

    //     // Deal user some collateral token
    //     deal(address(weth), USER, collateralAmount);

    //     // Prank USER
    //     vm.startPrank(USER);

    //     // Approve and deposit collateral
    //     IERC20(weth).approve(address(dsce), collateralAmount);
    //     dsce.depositCollateral(address(weth), collateralAmount);

    //     // Mint DSC
    //     dsce.mintDsc(mintAmount);

    //     // Act
    //     dsce.burnDsc(20 ether); // burn some DSC

    //     // Assert
    //     uint256 healthFactor = dsce.getHealthFactor(USER);
    //     assertGt(healthFactor, 1e18); // health factor should be > 1

    //     vm.stopPrank();
    // }

    // function testBurnOnlyAffectsMsgSender() public {
    //     uint256 mintAmount = 100 ether;
    //     address attacker = address(0xBEEF);

    //     // Label for better trace
    //     vm.label(attacker, "Attacker");

    //     // Mint DSC to USER
    //     vm.startPrank(USER);
    //     dsce.mintDsc(mintAmount);
    //     vm.stopPrank();

    //     // Log balances
    //     console.log("Attacker DSC balance: %s", dsc.balanceOf(attacker));
    //     console.log("Attacker allowance to Engine: %s", dsc.allowance(attacker, address(dsce)));

    //     // Check balance is zero
    //     assertEq(dsc.balanceOf(attacker), 0);

    //     // Expect revert due to no balance or allowance
    //     vm.startPrank(attacker);
    //     vm.expectRevert();
    //     dsce.burnDsc(10 ether);
    //     vm.stopPrank();
    // }

    function testHealthFactorRemainsValidAfterPartialBurn() public {
        uint256 depositAmount = 10 ether;
        uint256 mintAmount = 5 ether;

        deal(address(weth), USER, depositAmount);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), depositAmount);
        dsce.depositCollateral(address(weth), depositAmount);
        dsce.mintDsc(mintAmount);

        dsc.approve(address(dsce), mintAmount / 2);
        dsce.burnDsc(mintAmount / 2);

        uint256 healthFactor = dsce._healthFactor(USER); // Make public or via test helper if needed
        assertGe(healthFactor, 1e18);
        vm.stopPrank();
    }

    // function testLiquidationOnlyWhenHealthFactorBroken() public {
    //     address LIQUIDATOR = makeAddr("liquidator");

    //     uint256 deposit = 100 ether;
    //     uint256 mint = 90 ether;

    //     deal(address(weth), USER, deposit);
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), deposit);
    //     dsce.depositCollateral(weth, deposit);
    //     dsce.mintDsc(mint);
    //     vm.stopPrank();

    //     vm.startPrank(LIQUIDATOR);
    //     dsc.mint(LIQUIDATOR, mint);
    //     dsc.approve(address(dsce), mint);

    //     vm.expectRevert(DSCEngine.DSCEngine_HealthFactorOk.selector);
    //     dsce.liquidate(weth, USER, mint);
    //     vm.stopPrank();
    // }

    // function testCanLiquidateUserWhenHealthFactorIsLow() public {
    //     address LIQUIDATOR = makeAddr("liquidator");

    //     // Lower price of collateral to trigger liquidation
    //     // e.g., mock the priceFeed to return half price via mock interface

    //     uint256 deposit = 100 ether;
    //     uint256 mint = 90 ether;

    //     deal(address(weth), USER, deposit);
    //     deal(address(dsc), LIQUIDATOR, mint);

    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), deposit);
    //     dsce.depositCollateral(weth, deposit);
    //     dsce.mintDsc(mint);
    //     vm.stopPrank();

    //     vm.startPrank(LIQUIDATOR);
    //     dsc.approve(address(dsce), mint);
    //     dsce.liquidate(weth, USER, mint);
    //     vm.stopPrank();

    //     // Assert user DSC minted reduced
    //     (uint256 userDscMinted,) = dsce.getAccountInformation(USER);
    //     assertLt(userDscMinted, mint);
    // }

    function testGetHealthFactorReturnsCorrectValue() public {
        uint256 depositAmount = 10 ether;
        uint256 mintAmount = 5 ether;

        deal(address(weth), USER, depositAmount);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), depositAmount);
        dsce.depositCollateral(address(weth), depositAmount);
        dsce.mintDsc(mintAmount);
        vm.stopPrank();

        uint256 healthFactor = dsce._healthFactor(USER); // again, make public if not
        assertGt(healthFactor, 1e18);
    }

    // function testFullLifecycle() public {
    //     uint256 deposit = 10 ether;
    //     uint256 mint = 5 ether;

    //     deal(address(weth), USER, deposit);
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), deposit);

    //     dsce.depositCollateral(address(weth), deposit);
    //     dsce.mintDsc(mint);

    //     dsc.approve(address(dsce), mint);
    //     dsce.burnDsc(mint);
    //     dsce.redeemCollateral(address(weth), deposit);
    //     vm.stopPrank();

    //     assertEq(dsc.balanceOf(USER), 0);
    //     assertEq(dsce.getCollateralBalanceOfUser(USER, address(weth)), 0);
    // }

    // function testMintingRevertsIfHealthFactorBreaks() public {
    //     uint256 deposit = 10 ether;
    //     uint256 mint = 20 ether; // overcollateralization not maintained

    //     deal(address(weth), USER, deposit);
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), deposit);
    //     dsce.depositCollateral(address(weth), deposit);

    //     vm.expectRevert(DSCEngine.DSCEngine_BreaksHealthFactor.selector);
    //     dsce.mintDsc(mint);
    //     vm.stopPrank();
    // }

    function testBurningMoreThanMintedFails() public {
        uint256 deposit = 10 ether;
        uint256 mint = 5 ether;

        deal(address(weth), USER, deposit);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), deposit);
        dsce.depositCollateral(address(weth), deposit);
        dsce.mintDsc(mint);

        dsc.approve(address(dsce), mint + 1 ether);

        vm.expectRevert(); // TransferFrom would fail or _burn would revert
        dsce.burnDsc(mint + 1 ether);
        vm.stopPrank();
    }
}
