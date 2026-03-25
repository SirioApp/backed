// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract ContractAllowlist {
    address public admin;
    mapping(address => bool) public isAllowed;

    event ContractAdded(address indexed target);
    event ContractRemoved(address indexed target);
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    error Unauthorized();
    error InvalidAddress();
    error AlreadyAllowed();
    error NotAllowed();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    constructor(address admin_) {
        if (admin_ == address(0)) revert InvalidAddress();
        admin = admin_;
    }

    function addContract(address target) external onlyAdmin {
        if (target == address(0)) revert InvalidAddress();
        if (isAllowed[target]) revert AlreadyAllowed();
        isAllowed[target] = true;
        emit ContractAdded(target);
    }

    function removeContract(address target) external onlyAdmin {
        if (!isAllowed[target]) revert NotAllowed();
        isAllowed[target] = false;
        emit ContractRemoved(target);
    }

    function addContracts(address[] calldata targets) external onlyAdmin {
        for (uint256 i; i < targets.length; ++i) {
            if (targets[i] == address(0)) revert InvalidAddress();
            if (isAllowed[targets[i]]) revert AlreadyAllowed();
            isAllowed[targets[i]] = true;
            emit ContractAdded(targets[i]);
        }
    }

    function removeContracts(address[] calldata targets) external onlyAdmin {
        for (uint256 i; i < targets.length; ++i) {
            if (!isAllowed[targets[i]]) revert NotAllowed();
            isAllowed[targets[i]] = false;
            emit ContractRemoved(targets[i]);
        }
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert InvalidAddress();
        address previous = admin;
        admin = newAdmin;
        emit AdminTransferred(previous, newAdmin);
    }
}
