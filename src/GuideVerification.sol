// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract GuideVerification {
    // ========= 구조체 =========
    struct Guide {
        uint feedbackCount;
        uint matchCount;
        bool isVerified;
        uint totalExpertise;
        uint totalHelp;
        uint totalRecommend;
        uint totalRatings;
    }

    struct Rating {
        uint8 expertise;
        uint8 help;
        uint8 recommend;
        address rater;
    }

    struct Feedback {
        address guide;
        string content;
        Rating[] ratings;
        mapping(address => bool) hasRated; // 같은 사용자의 중복 평가 방지
        uint timestamp;
    }

    // ========= 상태 변수 =========
    mapping(address => Guide) public guides;
    Feedback[] public feedbacks;
    address public admin;
    uint public constant MIN_TOTAL_RATINGS = 10;
    uint public constant MIN_METRIC_AVG = 3 * 1000; // 3.0 이상
    uint public constant MIN_TOTAL_AVG = 4 * 1000;  // 4.0 이상

    // (선택) 토큰 발행 관련
    mapping(address => uint) public tokenBalance;
    uint public constant REWARD_AMOUNT = 100 ether; // 예시 단위

    // ========= 이벤트 =========
    event GuideRegistered(address indexed guide);
    event GuideStatusChanged(address indexed guide, bool isVerified);
    event FeedbackSubmitted(uint indexed feedbackId, address indexed guide, string content);
    event FeedbackRated(uint indexed feedbackId, address indexed guide, address indexed rater, uint8 exp, uint8 help, uint8 rec);
    event TokenRewarded(address indexed guide, uint amount);

    // ========= 접근제어 =========
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyVerifiedGuide() {
        require(guides[msg.sender].isVerified, "Only verified guides can call");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    // ========= 2. 가이드 등록 =========
    function registerGuide() external {
        require(!guides[msg.sender].isVerified && guides[msg.sender].feedbackCount == 0, "Already guide");
        guides[msg.sender] = Guide(0, 0, false, 0, 0, 0, 0);
        emit GuideRegistered(msg.sender);
    }

    // ========= 3. 피드백 제출 =========
    function submitFeedback(string memory content) external {
        require(!guides[msg.sender].isVerified, "Verified guides cannot submit feedback");

        Feedback storage fb = feedbacks.push();
        fb.guide = msg.sender;
        fb.content = content;
        fb.timestamp = block.timestamp;

        guides[msg.sender].feedbackCount++;
        emit FeedbackSubmitted(feedbacks.length - 1, msg.sender, content);
    }

    // ========= 3. 피드백 평가 =========
    function rateFeedback(
        uint feedbackId,
        uint8 expertise,
        uint8 help,
        uint8 recommend
    ) external onlyVerifiedGuide {
        require(feedbackId < feedbacks.length, "Invalid feedback ID");
        require(expertise >= 1 && expertise <= 5, "exp 1-5");
        require(help >= 1 && help <= 5, "help 1-5");
        require(recommend >= 1 && recommend <= 5, "rec 1-5");

        Feedback storage fb = feedbacks[feedbackId];
        require(fb.guide != msg.sender, "Cannot rate own feedback");
        require(!fb.hasRated[msg.sender], "Already rated");

        fb.ratings.push(Rating(expertise, help, recommend, msg.sender));
        fb.hasRated[msg.sender] = true; // 중복 방지

        Guide storage g = guides[fb.guide];
        g.totalExpertise += expertise;
        g.totalHelp += help;
        g.totalRecommend += recommend;
        g.totalRatings++;

        emit FeedbackRated(feedbackId, fb.guide, msg.sender, expertise, help, recommend);

        _checkVerification(fb.guide);
    }

    // ========= 4. 검증 조건 체크 및 자동 상태 변경 =========
    function _checkVerification(address guideAddr) internal {
        Guide storage g = guides[guideAddr];

        // 조건 1: 총 평가 수
        if (g.totalRatings < MIN_TOTAL_RATINGS) {
            _setGuideVerified(guideAddr, false);
            return;
        }

        // 조건 2: 모든 피드백이 적어도 1개 평가
        for (uint i = 0; i < feedbacks.length; i++) {
            if (feedbacks[i].guide == guideAddr && feedbacks[i].ratings.length == 0) {
                _setGuideVerified(guideAddr, false);
                return;
            }
        }

        // 조건 3, 4: 평균 점수
        uint avgExpTimes1000 = (g.totalExpertise * 1000) / g.totalRatings;
        uint avgHelpTimes1000 = (g.totalHelp * 1000) / g.totalRatings;
        uint avgRecTimes1000 = (g.totalRecommend * 1000) / g.totalRatings;
        uint totalAvgTimes1000 = ((g.totalExpertise + g.totalHelp + g.totalRecommend) * 1000) / (g.totalRatings * 3);

        if (avgExpTimes1000 >= MIN_METRIC_AVG && avgHelpTimes1000 >= MIN_METRIC_AVG && avgRecTimes1000 >= MIN_METRIC_AVG && totalAvgTimes1000 >= MIN_TOTAL_AVG) {
            _setGuideVerified(guideAddr, true);
        } else {
            _setGuideVerified(guideAddr, false);
        }
    }

    function _setGuideVerified(address guideAddr, bool verified) internal {
        if (guides[guideAddr].isVerified != verified) {
            guides[guideAddr].isVerified = verified;
            emit GuideStatusChanged(guideAddr, verified);
            if (verified) {
                _rewardGuide(guideAddr); // 조건 만족시 보상 지급
            }
        }
    }

    // ========= (선택) 5. 토큰 보상 기능 =========
    function _rewardGuide(address guideAddr) internal {
        tokenBalance[guideAddr] += REWARD_AMOUNT;
        emit TokenRewarded(guideAddr, REWARD_AMOUNT);
    }

    // ========= 관리자 전용 매칭 횟수 설정 =========
    function setMatchCount(address guideAddr, uint count) external onlyAdmin {
        guides[guideAddr].matchCount = count;
    }

    // ========= 데이터 조회 =========
    function getGuideStatus(address guideAddr) external view returns (string memory) {
        Guide storage g = guides[guideAddr];
        if (!g.isVerified && g.totalRatings < MIN_TOTAL_RATINGS) return "In progress";
        if (!g.isVerified && g.totalRatings >= MIN_TOTAL_RATINGS) return "Almost";
        if (g.isVerified) return "Formal Guide";
        return "In progress";
    }

    function getFeedback(uint feedbackId) external view returns (
        address guide,
        string memory content,
        uint ratingCount,
        uint timestamp
    ) {
        require(feedbackId < feedbacks.length, "Invalid ID");
        Feedback storage fb = feedbacks[feedbackId];
        return (fb.guide, fb.content, fb.ratings.length, fb.timestamp);
    }

    function getFeedbackCount() external view returns (uint) {
        return feedbacks.length;
    }
}
