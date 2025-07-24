//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
//import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

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
}
