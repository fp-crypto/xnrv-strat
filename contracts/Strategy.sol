// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

interface IXNrv is IERC20 {
    function enter(uint256 _amount) external;

    function leave(uint256 _share) external;
}

interface INrvMastermind {
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function poolInfo(uint256 _pid)
        external
        view
        returns (
            address,
            uint256,
            uint256,
            uint256
        );

    function userInfo(uint256 _pid, address user)
        external
        view
        returns (uint256, uint256);

    function pendingNerve(uint256 _pid, address _user)
        external
        view
        returns (uint256);
}

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    IXNrv xNrv = IXNrv(address(0x15B9462d4Eb94222a7506Bc7A25FB27a2359291e));
    INrvMastermind mastermind =
        INrvMastermind(address(0x2EBe8CDbCB5fB8564bC45999DAb8DA264E31f24E));
    uint256 pid = 2;

    constructor(address _vault) public BaseStrategy(_vault) {
        IERC20(want).safeApprove(address(xNrv), type(uint256).max);
        IERC20(xNrv).safeApprove(address(mastermind), type(uint256).max);
    }

    function name() external view override returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "StrategyNerveXNRV";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        (uint256 deposited, ) = mastermind.userInfo(pid, address(this));
        return
            want
                .balanceOf(address(this))
                .add(xNrv.balanceOf(address(this)))
                .add(deposited);
    }

    function pendingReward() public view returns (uint256) {
        return mastermind.pendingNerve(pid, address(this));
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        mastermind.deposit(pid, 0);

        uint256 assets = estimatedTotalAssets();
        uint256 wantBal = want.balanceOf(address(this));

        uint256 debt = vault.strategies(address(this)).totalDebt;

        if (assets >= debt) {
            _debtPayment = _debtOutstanding;
            _profit = assets - debt;

            uint256 amountToFree = _profit.add(_debtPayment);

            if (amountToFree > 0 && wantBal < amountToFree) {
                liquidatePosition(amountToFree);

                uint256 newLoose = want.balanceOf(address(this));

                //if we dont have enough money adjust _debtOutstanding and only change profit if needed
                if (newLoose < amountToFree) {
                    if (_profit > newLoose) {
                        _profit = newLoose;
                        _debtPayment = 0;
                    } else {
                        _debtPayment = Math.min(
                            newLoose - _profit,
                            _debtPayment
                        );
                    }
                }
            }
        } else {
            //serious loss should never happen but if it does lets record it accurately
            _loss = debt - assets;
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }

        uint256 wantBalance = want.balanceOf(address(this));
        if (wantBalance > 0) {
            xNrv.enter(want.balanceOf(address(this)));
        }

        uint256 xNrvBalance = xNrv.balanceOf(address(this));
        if (xNrvBalance > 0) {
            mastermind.deposit(pid, xNrvBalance);
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 totalAssets = want.balanceOf(address(this));
        if (_amountNeeded > totalAssets) {
            uint256 amountToFree = _amountNeeded.sub(totalAssets);

            (uint256 deposited, ) = mastermind.userInfo(pid, address(this));
            if (deposited < amountToFree) {
                amountToFree = deposited;
            }
            if (deposited > 0) {
                mastermind.withdraw(pid, amountToFree);
                xNrv.leave(xNrv.balanceOf(address(this)));
            }

            _liquidatedAmount = Math.min(
                _amountNeeded,
                want.balanceOf(address(this))
            );
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function prepareMigration(address _newStrategy) internal override {
        liquidatePosition(uint256(-1)); //withdraw all. does not matter if we ask for too much
    }

    function emergencyWithdrawal(uint256 _pid) external onlyGovernance {
        mastermind.emergencyWithdraw(_pid);
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}
}
