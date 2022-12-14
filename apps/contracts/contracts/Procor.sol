//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@semaphore-protocol/contracts/interfaces/IVerifier.sol";
import "@semaphore-protocol/contracts/base/SemaphoreCore.sol";
import "@semaphore-protocol/contracts/base/SemaphoreGroups.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Procor is SemaphoreCore, SemaphoreGroups, Ownable {

    event SessionCreated(uint256 indexed sessionId, string name, address owner, uint256 state, uint256 createdAt);
    event UserJoined(uint256 indexed sessionId, uint256 identityCommitment, uint256 joinedAt); 
    event QuestionAsked(uint256 indexed sessionId, uint256 indexed questionId, bytes32 question, uint256 askedAt);
    event QuestionVoted(uint256 indexed sessionId, uint256 indexed questionId, uint256 votes, uint256 votedAt);


    // state
    mapping(uint256 => Session) public sessions;
    mapping(uint256 => uint256[]) public sessionIdentityCommitments;
    uint256[] public sessionIds;

    // verifier
    IVerifier public verifier;

    // constants
    uint256 constant MAX_QUESTIONS = 100;
    uint256 constant NOT_STARTED = 1;
    uint256 constant ACTIVE = 2;
    uint256 constant ENDED = 3;

    uint256 fee = 0;

    // structs

    struct Question {
        uint256 votes;
        bytes32 content;
    }

    struct Session {
        uint256 sessionId;
        address owner;
        uint256 state;
        string eventName;
        Question[] questions;
    }

    // modifiers
    modifier sessionActive(uint256 sessionId) {
        require(sessions[sessionId].state == ACTIVE, "Session is not active");
        _;
    }
    modifier sesionInactive(uint256 sessionId) {
        require(
            sessions[sessionId].state == NOT_STARTED,
            "Session is not inactive"
        );
        _;
    }
    modifier sessionExists(uint256 sessionId) {
        require(
            sessions[sessionId].owner != address(0),
            "Session does not exist"
        );
        _;
    }
    modifier onlySessionOwner(uint256 sessionId) {
        require(sessions[sessionId].owner == msg.sender, "Not session owner");
        _;
    }
    modifier notOverQuestionLimit(uint256 sessionId) {
        require(
            sessions[sessionId].questions.length < MAX_QUESTIONS,
            "Question limit reached"
        );
        _;
    }

    // cosntructor
    constructor(address _verifier) {
        verifier = IVerifier(_verifier);
    }

    // make session
    function createSession(uint256 sessionId, string memory eventName) external payable {
        require(msg.value >= fee, "insufficient funds");
        _createGroup(sessionId, 20, 0);

        sessions[sessionId].sessionId = sessionId;
        sessions[sessionId].owner = msg.sender;
        sessions[sessionId].state = NOT_STARTED;
        sessions[sessionId].eventName = eventName;

        sessionIds.push(sessionId);

        emit SessionCreated(sessionId, eventName, msg.sender, NOT_STARTED, block.timestamp);

    }

    // start session
    function startSession(uint256 sessionId)
        external
        sessionExists(sessionId)
        onlySessionOwner(sessionId)
    {
        sessions[sessionId].state = ACTIVE;
    }

    // end session
    function endSession(uint256 sessionId)
        external
        sessionExists(sessionId)
        onlySessionOwner(sessionId)
        sessionActive(sessionId)
    {
        sessions[sessionId].state = ENDED;
    }

    // join session
    function joinSession(uint256 sessionId, uint256 identityCommitment)
        external
        sessionExists(sessionId)
        sessionActive(sessionId)
    {
        _addMember(sessionId, identityCommitment);
        sessionIdentityCommitments[sessionId].push(identityCommitment);
    }

    function getIdentityCommitments(uint256 sessionId)
        external
        view
        returns (uint256[] memory)
    {
        return sessionIdentityCommitments[sessionId];
    }

    // ask question
    function postQuestion(
        uint256 sessionId,
        bytes32 quesiton,
        uint256 root,
        uint256 nullifierHash,
        uint256[8] calldata proof
    )
        external
        sessionExists(sessionId)
        sessionActive(sessionId)
        notOverQuestionLimit(sessionId)
    {
        _verifyProof(
            quesiton,
            root,
            nullifierHash,
            sessionId,
            proof,
            verifier
        );

        Question memory q = Question({votes: 0, content: quesiton});
        sessions[sessionId].questions.push(q);

        _saveNullifierHash(nullifierHash);

        emit QuestionAsked(sessionId, sessions[sessionId].questions.length - 1, quesiton, block.timestamp);
    }

    // vote for question
    // exeernal nulifiers will be sessionId *1000 + questionId
    function voteQuestion(
        bytes32 signal,
        uint256 root,
        uint256 nullifierHash,
        uint256 externalNullifier,
        uint256[8] calldata proof,
        uint256 sessionId,
        uint256 questionId
    )
        external
        sessionExists(externalNullifier / 1000)
        sessionActive(externalNullifier / 1000)
        returns (uint256, uint256)
    {
        _verifyProof(
            signal,
            root,
            nullifierHash,
            externalNullifier,
            proof,
            verifier
        );
        sessions[sessionId].questions[questionId].votes++;
        _saveNullifierHash(nullifierHash);

        emit QuestionVoted(sessionId, questionId, sessions[sessionId].questions[questionId].votes, block.timestamp);
        
        return (questionId, sessions[sessionId].questions[questionId].votes);
    }

    function withdrawFunds() external onlyOwner returns (uint256) {
        payable(owner()).transfer(address(this).balance);
        return address(this).balance;
    }

    function viewSessions() external view returns (Session[] memory){
        Session[] memory viewSessionsList = new Session[](sessionIds.length);
        for (uint256 i = 0; i < sessionIds.length; i++) {
            viewSessionsList[i] = sessions[sessionIds[i]];
        }
        return viewSessionsList;
    }

    function viewSessionIdentitiyCommitments(uint256 sessionId) external view returns (uint256[] memory){
        return sessionIdentityCommitments[sessionId];
    }
}
