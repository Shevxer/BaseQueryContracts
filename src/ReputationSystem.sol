// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ReputationSystem {
    error AlreadyVoted();
    error CannotVoteSelf();
    error InsufficientBalance();
    error NotAuthorized();

    struct UserReputation {
        uint256 score;
        uint256 totalVotes;
    }

    enum ContentType { QUESTION, ANSWER }

    mapping(address => UserReputation) public userReputation;
    mapping(bytes32 => mapping(address => bool)) public hasVoted;
    mapping(bytes32 => uint256) public upvoteCount;
    mapping(bytes32 => uint256) public downvoteCount;
    mapping(address => bool) public authorizedCallers;
    
    address public owner;
    uint256 public constant MIN_ETH_BALANCE = 1000000000000000; // 0.001 ether in wei

    event VoteCast(bytes32 indexed contentKey, address indexed voter, bool isUpvote);
    event ReputationUpdated(address indexed user, uint256 newScore);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(authorizedCallers[msg.sender] || msg.sender == owner, "Not authorized");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        authorizedCallers[caller] = authorized;
    }

    function canAnswer(address user) external view returns (bool) {
        return user.balance >= MIN_ETH_BALANCE;
    }

    function canVote(address user) external view returns (bool) {
        return user.balance >= MIN_ETH_BALANCE;
    }

    function vote(
        uint256 questionId,
        uint256 answerId,
        ContentType contentType,
        bool isUpvote,
        address contentOwner,
        address voter
    ) external onlyAuthorized {
        if (voter.balance < MIN_ETH_BALANCE) revert InsufficientBalance();
        if (voter == contentOwner) revert CannotVoteSelf();

        bytes32 contentKey = getContentKey(questionId, answerId, contentType);
        
        if (hasVoted[contentKey][voter]) revert AlreadyVoted();

        hasVoted[contentKey][voter] = true;

        if (isUpvote) {
            upvoteCount[contentKey]++;
            updateReputation(contentOwner, 2);
        } else {
            downvoteCount[contentKey]++;
            updateReputation(contentOwner, -1);
        }

        userReputation[voter].totalVotes++;

        emit VoteCast(contentKey, voter, isUpvote);
    }

    function updateReputation(address user, int256 change) public onlyAuthorized {
        UserReputation storage rep = userReputation[user];
        
        if (change < 0 && uint256(-change) > rep.score) {
            rep.score = 0;
        } else {
            rep.score = uint256(int256(rep.score) + change);
        }

        emit ReputationUpdated(user, rep.score);
    }

    function getVoteCount(
        uint256 questionId,
        uint256 answerId,
        ContentType contentType
    ) external view returns (uint256 upvotes, uint256 downvotes) {
        bytes32 contentKey = getContentKey(questionId, answerId, contentType);
        return (upvoteCount[contentKey], downvoteCount[contentKey]);
    }

    function getContentKey(
        uint256 questionId,
        uint256 answerId,
        ContentType contentType
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(questionId, answerId, contentType));
    }

    function getUserReputation(address user) external view returns (uint256 score, uint256 totalVotes) {
        UserReputation memory rep = userReputation[user];
        return (rep.score, rep.totalVotes);
    }
}