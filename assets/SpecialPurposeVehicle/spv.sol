pragma solidity ^0.4.2;

contract owned {
    address public owner;

    function owned() {
        owner = msg.sender;
    }

    modifier onlyOwner {
        if (msg.sender != owner) throw;
        _;
    }

    function transferOwnership(address newOwner) onlyOwner {
        owner = newOwner;
    }
}

contract tokenRecipient { function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData); }

contract Stromkonto is owned {
    function addTx(address _from,address _to, uint256 _value,string _txt)  { }
}

/** Special Purpose Vehicle - Contract der StromDAO (https://stromdao.de/)
 * Author: thorsten.zoerner(at)stromdao.de
 * Deployment: 
 *
 * Ein Special Purpose Vehicle ist eine Zweckgesellschaft, die lediglich festschreibt, wie Einnahmen unter den Anteilseignern aufgeteilt werden.
 *
 * Bei der Umsetzung der StromDAO wird das Stromkonto zur Verbuchung der Gutschriften verwendet. 
 * Eigentümer (owner) ist das Orakel, welches die Einnahmen erkennt und !eine! Transaktion auslöst
 * Der SPV-Contract verteilt diesen dann auf die einzelnen Stromkonten
 * 
 * Benötigt eine Freigabe des SPV-Vertrages im Balancer! ( 0xc3ef562cc403c8f9edf7c3826655fbf50f4ddde8:BalancerOracles.addOracle() )
 * 
 * Setup:
  => Eigentümer der Anlage legt neuen SPV() Vertrag an
  => Eigentümer verwendet SPV.transfer() um Eigentumsanteile zu verteilen
  => Eigentümer setzt Orakel als Einnahmenquelle
  => Eigentümer setzt Stromkonto (Smart Contract) für Verrechnung
 
 * Wirkbetrieb:
  => Orakel ruft SPV.addTx() auf mit dem Betrag, der verteilt werden soll
  => SPV.addTX() ermittelt die Gutschrift der einzelnen Besitzer
  => SPV.addTX() verteilt entsprechend und verbucht direkt im Stromkonto

 * Bedingungen:
   => SPV muss beim Stromkonto hinterlegt sein als zulässiges Oracle (erlaubt Stromkonto.addTX aufzurufen)

 * Implementiert einen ERC-20 Token
 */

contract SPV is owned {
     /* Public variables of the token */
    string public standard = 'Token 0.1';
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    address public oracle;
    uint256 public min_muxamount;
    
    Stromkonto public stromkonto;
    
    address[] public shareholders;
    
    /* This creates a map with all balances */
    mapping (address => uint256) public balanceOf;
    mapping (address => uint256) public bufferOf; //buffered Amount before demux
    mapping (address => mapping (address => uint256)) public allowance;

    /* This generates a public event on the blockchain that will notify clients */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /* Initializes contract with initial supply tokens to the creator of the contract */
    function SPV(
        uint256 initialSupply,
        string tokenName,
        string tokenSymbol
        ) {
        balanceOf[msg.sender] = initialSupply;   // Give the creator all initial tokens
        shareholders[shareholders.length]=msg.sender;
        totalSupply = initialSupply;             // Update total supply
        name = tokenName;                        // Set the name for display purposes
        symbol = tokenSymbol;                    // Set the symbol for display purposes
        decimals = 0;                            // Amount of decimals for display purposes (not supported for SPV)
    }

    /* Send coins */
    function transfer(address _to, uint256 _value) {
        if (balanceOf[msg.sender] < _value) throw;           // Check if the sender has enough
        if (balanceOf[_to] + _value < balanceOf[_to]) throw; // Check for overflows
        balanceOf[msg.sender] -= _value;                     // Subtract from the sender
        /* Check if we already know this shareholder from past - if not add this one */
        shareholders[shareholders.length]=_to;
        
        balanceOf[_to] += _value;                            // Add the same to the recipient
        Transfer(msg.sender, _to, _value);                   // Notify anyone listening that this transfer took place
    }

    function setOracle(address _oracle) onlyOwner {
        oracle=_oracle;
    }
    
    /* Set allowed Stromkonto Smart Contract */
    function setStromkonto(Stromkonto _stromkonto) onlyOwner {
        stromkonto=_stromkonto;
    }
    
    function setBufferAmount(uint256 _value) onlyOwner {
        min_muxamount=_value;
    }
    /* Allow another contract to spend some tokens in your behalf */
    function approve(address _spender, uint256 _value)
        returns (bool success) {
        allowance[msg.sender][_spender] = _value;
        return true;
    }

    /* Approve and then comunicate the approved contract in a single tx */
    function approveAndCall(address _spender, uint256 _value, bytes _extraData)
        returns (bool success) {
        tokenRecipient spender = tokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, this, _extraData);
            return true;
        }
    } 
    
    function addTx(uint256 amount) {
        if(msg.sender!=oracle) throw;
        if(amount<totalSupply) throw;
        
        mapping (address => uint256) txMapping;
        for(var i=0;i<shareholders.length;i++) {
            txMapping[shareholders[i]]=balanceOf[shareholders[i]];
        }   
        for(var j=0;j<shareholders.length;j++) {
            var share_amount=amount*(txMapping[shareholders[j]]/totalSupply);
            txMapping[shareholders[j]]=0;
            //=> Transfer the share_amount
            if(share_amount>0) {
                bufferOf[shareholders[j]]+=share_amount;
                if(bufferOf[shareholders[j]]>min_muxamount) {
                    stromkonto.addTx(this,shareholders[j],share_amount,'SPV');
                    bufferOf[shareholders[j]]=0;
                }
            }
        }
    }

    /* A contract attempts to get the coins */
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        if (balanceOf[_from] < _value) throw;                 // Check if the sender has enough
        if (balanceOf[_to] + _value < balanceOf[_to]) throw;  // Check for overflows
        if (_value > allowance[_from][msg.sender]) throw;   // Check allowance
        balanceOf[_from] -= _value;                          // Subtract from the sender
        balanceOf[_to] += _value;                            // Add the same to the recipient
        shareholders[shareholders.length]=_to;
        allowance[_from][msg.sender] -= _value;
        Transfer(_from, _to, _value);
        return true;
    }

    /* This unnamed function is called whenever someone tries to send ether to it */
    function () {
        throw;     // Prevents accidental sending of ether
    }
    
}

