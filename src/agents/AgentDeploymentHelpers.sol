// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Sale} from "../launch/Sale.sol";
import {AgentExecutor} from "./AgentExecutor.sol";
import {ISale} from "../interfaces/ISale.sol";

interface ISaleDeployer {
    function deploySale(
        address collateral,
        address treasury,
        address founder,
        uint256 duration,
        uint256 launchTime,
        uint256 lockupMinutes,
        string calldata tokenName,
        string calldata tokenSymbol,
        address factory,
        ISale.SaleConfigSnapshot calldata saleConfig,
        uint256 projectId
    ) external returns (address sale);
}

interface IAgentExecutorDeployer {
    function deployExecutor(address agent, address treasury, address allowlist, address admin)
        external
        returns (address executor);
}

contract SaleDeployer is ISaleDeployer {
    function deploySale(
        address collateral,
        address treasury,
        address founder,
        uint256 duration,
        uint256 launchTime,
        uint256 lockupMinutes,
        string calldata tokenName,
        string calldata tokenSymbol,
        address factory,
        ISale.SaleConfigSnapshot calldata saleConfig,
        uint256 projectId
    ) external returns (address sale) {
        sale = address(
            new Sale(
                collateral,
                treasury,
                founder,
                duration,
                launchTime,
                lockupMinutes,
                tokenName,
                tokenSymbol,
                factory,
                saleConfig,
                projectId
            )
        );
    }
}

contract AgentExecutorDeployer is IAgentExecutorDeployer {
    function deployExecutor(address agent, address treasury, address allowlist, address admin)
        external
        returns (address executor)
    {
        executor = address(new AgentExecutor(agent, treasury, allowlist, admin));
    }
}
