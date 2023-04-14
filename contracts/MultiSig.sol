//SPDX-License-Identifier:MIT
pragma solidity ^0.8.17;

contract MultiSig {

    //EVENTS

    event Deposit(address indexed sender, uint value);
    event NewOwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event OwnerReplaced(address indexed owner, address indexed newOwner);
    event RequirementUpdated(uint required);
    event transactionIsConfirmed(address indexed sender, uint indexed transactionId);
    event transactionIsRevoked(address indexed sender, uint indexed transactionId);
    event transactionExecution(uint indexed transactionId);
    event transactionExecutionFailure(uint indexed transactionId);
    event transactionSubmission(uint indexed transactionId);


    //MAX OWNERS 
    uint public immutable MAX_OWNERS;

    // Storage
    mapping (uint => Transaction) public transactions; 
    mapping (uint => mapping(address => bool)) public confirmations;
    mapping (address => bool) public isOwner;
    address[] public owners;
    uint public required;
    uint public transactionCount;

    struct Transaction {
        address destination;
        uint value;
        bytes data;
        bool executed;
    }

    //modifiers
    modifier Wallet() {
        require(msg.sender == address(this));
        _;
    }
    modifier ownerDoesNotExist(address owner) {
        require(!isOwner[owner]);
        _;
    }
     modifier ownerExist(address owner) {
        require(isOwner[owner]);
        _;
    }
    modifier checkparams(uint ownerCount, uint _required) {
        require(ownerCount <= MAX_OWNERS
        && _required <= ownerCount
        && _required != 0
            && ownerCount != 0);
        _;
    }
    modifier transactionValid(uint transactionId) {
        require(transactions[transactionId].destination != address(0));
        _;
    }

     modifier transactionConfirmed(uint transactionId, address owner) {
        require(!confirmations[transactionId][owner]);
        _;
    }

    modifier transactionNotConfirmed(uint transactionId, address owner) {
        require(!confirmations[transactionId][owner]);
        _;
    }
    
    modifier transactionNotExecuted(uint transactionId) {
        require(!transactions[transactionId].executed);
        _;
    }

     receive() external
    payable
    {
        if (msg.value > 0)
            emit Deposit(msg.sender, msg.value);
    }

    fallback()external {}
    constructor(address[] memory _owners, uint _maxOwnerCount, uint _required ) {
        owners = _owners;
        MAX_OWNERS = _maxOwnerCount;
        required = _required;

    }
    /// @dev Allows to add a new owner. Transaction has to be sent by wallet.
    /// @param _owner Address of new owner.

    function addOwner(address _owner) public Wallet ownerDoesNotExist(_owner) {
        require(_owner != address(0), "WALLET: INVALID_ADDRESS");
        isOwner[_owner] = true;
        owners.push(_owner);
        emit NewOwnerAdded(_owner);
    }

    /// @dev remove owner of the Wallet
    /// @param _owner address to be removed 

    function removeOwner(address _owner) public Wallet ownerExist(_owner) {
        isOwner[_owner] = false;
        for(uint i = 0; i < owners.length - 1; i++) {
            if(owners[i] == _owner) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
            }
            
                changeRequirement(owners.length);
             emit OwnerRemoved(_owner);
        }

    }
    /// @dev Allows to replace an owner with a new owner. Transaction has to be sent by wallet.
    /// @param _owner Address of owner to be replaced.
    /// @param _newOwner Address of new owner.

    function replaceOwner(address _owner, address _newOwner) public Wallet ownerExist(_owner) ownerDoesNotExist(_newOwner) {
         for(uint i = 0; i<owners.length - 1;i++) {
            if(owners[i] == _owner) {
                owners[i] = _newOwner;
            }
            isOwner[_owner] = false;
            isOwner[_newOwner] = true;
            emit OwnerReplaced(_owner, _newOwner);

         }
    }
    /// @dev Allows to change the number of required confirmations. Transaction has to be sent by wallet.
    /// @param _required Number of required confirmations.
    function changeRequirement(uint _required) public Wallet checkparams(owners.length, _required) {
        required = _required;
        emit RequirementUpdated(required);
    }

    /// @dev Allows an owner to submit and confirm a transaction.
    /// @param _destination Transaction target address.
    /// @param _value Transaction ether value.
    /// @param _data Transaction data payload.
    /// @return transactionID transaction ID.
    function submitTransaction(address _destination, uint _value, bytes memory _data) public returns(uint transactionID) {
        // transactionId = addTransaction(destination, value, data);
        // confirmTransaction(transactionId);
    }

    /// @dev Allows an owner to confirm a transaction.
    /// @param _transactionId Transaction ID.
    function confirmTransaction(uint _transactionId)
    public
    ownerExist(msg.sender)
    transactionValid(_transactionId)
    transactionNotConfirmed(_transactionId, msg.sender)
    {
        confirmations[_transactionId][msg.sender] = true;
        emit transactionIsConfirmed(msg.sender, _transactionId);
        // executeTransaction(_transactionId);
    }
     /// @dev Allows an owner to revoke a confirmation for a _transaction.
    /// @param _transactionId Transaction ID.

    function revokeTransaction(uint _transactionId) public ownerExist(msg.sender) transactionConfirmed(_transactionId, msg.sender)
    transactionNotExecuted(_transactionId) {
        confirmations[_transactionId][msg.sender] = false;

        emit transactionIsRevoked(msg.sender, _transactionId);
    }
    /// @dev Returns the confirmation status of a transaction.
    /// @param _transactionId Transaction ID.
    /// @return result Confirmation status.
    function isConfirmed(uint _transactionId) public view returns(bool result) {
        uint count = 0;
        result = false;

        for(uint i = 0; i <= owners.length -1; i++ ) {
            if(confirmations[_transactionId][msg.sender]) {
                count++;
            }
            if(count == required) {
                result = true;
            }
        }
    }


    /// @dev Allows anyone to execute a confirmed transaction.
    /// @param _transactionId Transaction ID.
    function executeTransaction(uint _transactionId) public ownerExist(msg.sender)  transactionConfirmed(_transactionId, msg.sender) transactionNotExecuted(_transactionId) {
        if(isConfirmed(_transactionId)) {
            Transaction storage txn = transactions[_transactionId];
            txn.executed = true;
            if (external_call(txn.destination, txn.value, txn.data.length, txn.data)) {
                emit transactionExecution(_transactionId);
            } else {
                emit transactionExecutionFailure(_transactionId);
                txn.executed = false;
            }
        }
    } 
     // call has been separated into its own function in order to take advantage
    // of the Solidity's code generator to produce a loop that copies tx.data into memory.
    function external_call(address destination, uint value, uint dataLength, bytes memory data) internal returns (bool result) {
        assembly {
            let x := mload(0x40)   // "Allocate" memory for output (0x40 is where "free memory" pointer is stored by convention)
            let d := add(data, 32) // First 32 bytes are the padded length of data, so exclude that
            result := call(
            gas(),   // 34710 is the value that solidity is currently emitting
            // It includes callGas (700) + callVeryLow (3, to pay for SUB) + callValueTransferGas (9000) +
            // callNewAccountGas (25000, in case the destination address does not exist and needs creating)
            destination,
            value,
            d,
            dataLength,        // Size of the input (in bytes) - this is what fixes the padding problem
            x,
            0                  // Output is ignored, therefore the output size is zero
            )
        }
    }

    /// @dev Adds a new transaction to the transaction mapping, if transaction does not exist yet.
    /// @param _destination Transaction target address.
    /// @param _value Transaction ether value.
    /// @param _data Transaction data payload.
    /// @return transactionId Returns transaction ID.

    function addTransaction(address _destination,  uint _value, bytes memory _data) internal  returns (uint transactionId) {
        require(_destination != address(0), "WALLET : DESTINATION_0");
        transactionId = transactionCount;
        transactions[transactionId] = Transaction({
            destination: _destination,
        value: _value,
        data: _data,
        executed: false
        });
        transactionCount++;
        emit transactionSubmission(transactionId);

    }


}