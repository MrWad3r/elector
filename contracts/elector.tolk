tolk 1.0

import "@stdlib/gas-payments"
import "@stdlib/lisp-lists"
import "@stdlib/tvm-dicts"
import "@stdlib/tvm-lowlevel"

const newStakeMessageTag = 0x4e73744b;
const recoverStakeMessageTag = 0x47657424;
const upgradeCodeMessageTag = 0x4e436f64;
const newComplaintMessageTag = 0x52674370;
const voteForComplaintMessageTag = 0x56744370;


struct Storage {
    curElect: dict
    credits: dict
    pastElections: dict
    grams: coins
    activeId: uint32
    activeHash: uint256
}

fun Storage.load() {
    return Storage.fromCell(contract.getData());
}

fun Storage.save(self) {
    contract.setData(self.toCell());
}

struct Election {
    electAt: uint32
    electClose: uint32
    minStake: coins
    totalStake: coins
    members: dict
    failed: bool
    finished: bool
}


struct PastElection {
    unfreezeAt: uint32
    stakeHeld: uint32
    vsetHash: uint256
    frozenDict: dict
    totalStake: coins
    bonuses: coins
    complaints: dict
}


fun PastElection.toBuilder(self): builder {
    return beginCell().storeAny(self)
}


struct (0x2d) ComplaintStatus {
    complaint: Cell<ValidatorComplaint>
    voters: dict
    vsetId: uint256
    weightRemaining: int64
}

fun ComplaintStatus.toBuilder(self): builder {
    return beginCell().storeAny(self)
}

struct (0xbc) ValidatorComplaint {
    validatorPubkey: uint256
    description: cell
    createdAt: uint32
    severity: uint8
    rewardAddr: uint256
    paid: coins
    suggestedFine: coins
    suggestedFinePart: uint32
}

fun ValidatorComplaint.toBuilder(self): builder {
    return beginCell().storeAny(self)
}

struct (0x1a) ComplaintPricing {
    deposit: coins
    bitPrice: coins
    cellPrice: coins
}

fun ComplaintPricing.load() {
    var param = blockchain.configParam(13);
    if (param == null) {
        return ComplaintPricing {
            deposit: 1 << 36,
            bitPrice: 1,
            cellPrice: 512,
        };
    } else {
        return ComplaintPricing.fromCell(param, {assertEndAfterReading: true});
    }
}

struct ValidatorConfig {
    electedFor: int32
    electionsBeginBefore: int32
    electionsEndBefore: int32
    stakeHeldFor: int32
}

fun ValidatorConfig.load() {
    var param = blockchain.configParam(15);
    return ValidatorConfig.fromCell(param!);
}

struct (0x12) ValidatorSet {
    utime_since: uint32
    utime_until: uint32
    total: uint16
    main: uint16
    totalWeight: uint64
    list: dict
}

struct CurrentVset {
    vset: Cell<ValidatorSet>
    totalWeight: uint64
    list: dict
}

fun CurrentVset.load() {
    val vset = blockchain.configParam(34)! as Cell<ValidatorSet>;

    var cs = lazy vset.load();

    return CurrentVset {
        vset,
        totalWeight: cs.totalWeight,
        list: cs.list,
    };
}

struct ValidatorDescr {
    value: slice?
    totalWeight: int
}

fun CurrentVset.getDescr(self, idx: int) {
    var (value, _found) = self.list.uDictGet(16, idx);
    return ValidatorDescr { value, totalWeight: self.totalWeight };
}

type ValidatorDescription = ValidatorDescrSimple | ValidatorDescrWithAddr;


struct (0x53) ValidatorDescrSimple {
    pubkeyTag: uint32 = 0x8e81278a  // ed25519_pubkey tag
    pubkey: uint256
    weight: uint64
}

struct (0x73) ValidatorDescrWithAddr {
    pubkeyTag: uint32 = 0x8e81278a  // ed25519_pubkey tag
    pubkey: uint256
    weight: uint64
    adnlAddr: uint256
}

fun ValidatorDescr.loadValidatorInfo(cs: slice): ValidatorInfo {
    val descr = lazy ValidatorDescription.fromSlice(cs);
    var pubkey: uint256;
    var weight: uint64;
    match (descr) {
        ValidatorDescrSimple => {
            assert(descr.pubkeyTag == 0x8e81278a, 41);
            pubkey = descr.pubkey;
            weight = descr.weight;
        }
        ValidatorDescrWithAddr => {
            assert(descr.pubkeyTag == 0x8e81278a, 41);
            pubkey = descr.pubkey;
            weight = descr.weight;
        }
        else => throw 41
    }

    return ValidatorInfo { pubkey, weight};
}

struct ValidatorInfo {
    pubkey: uint256
    weight: uint64
}


struct UnfreezeResult {
    credits: dict
    recovered: coins
}


struct PunishResult {
    credits: dict
    frozen: dict
    fineUnalloc: coins
    fineCollected: coins
}

struct ExtendedParticipationList {
    electAt: uint32,
    electClose: uint32,
    minStake: coins,
    totalStake: coins,
    participants: tuple,
    failed: bool,
    finished: bool
}


fun sendMessageBack(
    dest: address,
    functionTag: uint32,
    queryId: uint64,
    body: uint32,
    grams: coins,
    mode: int,
) {
    var outMessage: OutMessage;

    if (body >= 0) {
        outMessage = createMessage({
            bounce: true,
            value: grams,
            dest,
            body: (functionTag, queryId, body),
        });
    } else {
        outMessage = createMessage({
            bounce: true,
            value: grams,
            dest,
            body: (functionTag, queryId),
        });
    }

    outMessage.send(mode);
}

fun returnStake(addr: address, queryId: int, reason: int) {
    sendMessageBack(
        addr,
        0xee6f454c,
        queryId,
        reason,
        0,
        SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE
    );
}

fun sendConfirmation(addr: address, queryId: int, comment: int) {
    sendMessageBack(addr, 0xf374484c, queryId, comment, ton("1"), SEND_MODE_IGNORE_ERRORS);
}

fun sendValidatorSetToConfig(configAddr: int, vset: cell, queryId: int) {
    var msg = beginCell()
        .storeUint(0xc4ff, 17) // 0 11000100 0xff
        .storeUint(configAddr, 256)
        .storeCoins(ton("1")) // ~1 gram of value to process and obtain answer
        .storeUint(0, 1 + 4 + 4 + 64 + 32 + 1 + 1)
        .storeUint(0x4e565354, 32)
        .storeUint(queryId, 64)
        .storeRef(vset)
        .endCell();

    sendRawMessage(msg, SEND_MODE_PAY_FEES_SEPARATELY);
}


fun creditTo(credits: dict, addr: int, amount: coins): dict {
    val (valueOpt, found) = credits.uDictGet(256, addr);
    if (found) {
        var value = valueOpt!;
        amount += value.loadCoins();
    }
    credits.uDictSetBuilder(256, addr, beginCell().storeCoins(amount));
    return credits;
}


fun processSimpleTransfer(sAddr: address, msgValue: coins) {
    var data = Storage.load();
    val (srcWc, srcAddr) = sAddr.getWorkchainAndHash();
    if ((srcAddr != 0) | ((srcWc + 1) != BASECHAIN) | (data.activeId == 0)) {
        //TODO: check
        // simple transfer to us (credit "nobody's" account)
        data.grams += msgValue;
        Storage.save(data);
        return;
    }

    // zero source address -1:00..00 (collecting validator fees)
    val (fs, found) = data.pastElections.uDictGet(32, data.activeId);
    if (!found) {
        data.grams += msgValue;
    } else {
        var pe = PastElection.fromSlice(fs!, { assertEndAfterReading: true });
        pe.bonuses += msgValue;
        data.pastElections.uDictSetBuilder(32, data.activeId, pe.toBuilder());
    }

    data.save();
}


fun processNewStake(sAddr: address, msgValue: coins, cs: slice, queryId: int) {
    val (srcWc, srcAddr) = sAddr.getWorkchainAndHash();
    var ds = contract.getData().beginParse();
    val electionDict = ds.loadDict();
    if (electionDict == null || (srcWc + 1) != BASECHAIN) {
        // no elections active, or source is not in masterchain
        returnStake(sAddr, queryId, 0);
        return;
    }

    // parse the remainder of new stake message
    val validatorPubkey = cs.loadUint(256);
    val stakeAt = cs.loadUint(32);
    val maxFactor = cs.loadUint(32);
    val adnlAddr = cs.loadUint(256);
    val signature = cs.loadRef().beginParse().preloadBits(512);
    cs.assertEnd();

    if (
        !isSliceSignatureValid(
                beginCell()
                        .storeUint(0x654c5074, 32)
                        .storeUint(stakeAt, 32)
                        .storeUint(maxFactor, 32)
                        .storeUint(srcAddr, 256)
                        .storeUint(adnlAddr, 256)
                        .endCell()
                        .beginParse(),
            signature,
            validatorPubkey
        )
    ) {
        // incorrect signature, return stake
        returnStake(sAddr, queryId, 1);
        return;
    }

    if (maxFactor < 0x10000) {
        // factor must be >= 1. = 65536/65536
        returnStake(sAddr, queryId, 6);
        return;
    }

    // parse current election data
    var election = Election.fromCell(electionDict!, { assertEndAfterReading: true });
    msgValue -= ton("1"); // deduct GR$1 for sending confirmation
    if ((msgValue << 12) < election.totalStake) {
        // stake smaller than 1/4096 of the total accumulated stakes, return
        returnStake(sAddr, queryId, 2);
        return;
    }

    election.totalStake += msgValue; // (provisionally) increase total stake
    if (stakeAt != election.electAt) {
        // stake for some other elections, return
        returnStake(sAddr, queryId, 3);
        return;
    }
    if (election.finished) {
        // elections already finished, return stake
        returnStake(sAddr, queryId, 0);

        return;
    }
    var (member, found) = election.members.uDictGet(256, validatorPubkey);
    if (found) {
        // entry found, merge stakes
        msgValue += member!.loadCoins();
        member!.skipBits(64); // skip timestamp and max_factor
        found = (srcAddr != member!.loadUint(256));
    }
    if (found) {
        // can make stakes for a public key from one address only
        returnStake(sAddr, queryId, 4);
        return;
    }
    if (msgValue < election.minStake) {
        // stake too small, return it
        returnStake(sAddr, queryId, 5);
        return;
    }
    assert(msgValue > 0, 44);

    acceptExternalMessage();

    // store stake in the dictionary
    election.members.uDictSetBuilder(
        256,
        validatorPubkey,
        beginCell().storeCoins(msgValue).storeUint(blockchain.now(), 32).storeUint(maxFactor, 32)
            .storeUint(srcAddr, 256)
            .storeUint(adnlAddr, 256)
    );
    // gather and save election data
    val new_elect_dict = Election.toCell(election);
    contract.setData(beginCell().storeDict(new_elect_dict).storeSlice(ds).endCell());
    // return confirmation message
    if (queryId != 0) {
        sendConfirmation(sAddr, queryId, 0);
    }
}


fun unfreezeWithoutBonuses(credits: dict, freezeDict: dict, totStakes: coins): UnfreezeResult {
    var new_credits = credits;
    var total: coins = 0;
    var recovered: coins = 0;
    var pubkey = -1;
    do {
        var (nextKey, csOpt, found) = freezeDict.uDictGetNext(256, pubkey);
        if (found) {
            pubkey = nextKey!;
            var cs = csOpt!;

            val addr = cs.loadUint(256);
            val _weight = cs.loadUint(64);
            val stake = cs.loadCoins();
            val banned = cs.loadInt(1) != 0;
            cs.assertEnd();

            if (banned) {
                recovered += stake;
            } else {
                new_credits = creditTo(new_credits, addr, stake);
            }
            total += stake;
        }
    } while (found);
    assert(total == totStakes, 59);
    return UnfreezeResult {credits: new_credits, recovered};
}

fun unfreezeWithBonuses(credits: dict, freezeDict: dict, totStakes: coins, totBonuses: coins): UnfreezeResult {

    var total: coins = 0;
    var recovered: coins = 0;
    var returnedBonuses: coins = 0;
    var pubkey = -1;
    do {
        var (nextKey, csOpt, found) = freezeDict.uDictGetNext(256, pubkey);
        if (found) {
            pubkey = nextKey!;
            var cs = csOpt!;
            val addr = cs.loadUint(256);
            val _ = cs.loadUint(64); //weight
            val stake = cs.loadCoins();
            val banned = cs.loadInt(1) != 0;
            cs.assertEnd();

            if (banned) {
                recovered += stake;
            } else {
                var bonus = coinsMuldiv(totBonuses, stake, totStakes);
                returnedBonuses += bonus;
                credits = creditTo(credits, addr, stake + bonus);
            }
            total += stake;
        }
    } while (found);
    assert((total == totStakes) & (returnedBonuses <= totBonuses), 59);
    return UnfreezeResult { credits, recovered: recovered + totBonuses - returnedBonuses };
}

fun unfreezeAll(credits: dict, pastElections: dict, electId: int): (dict, dict, coins) {
    var (fsOpt, found) = pastElections.uDictDeleteAndGet(32, electId);
    if (!found) {
        // no elections with this id
        return (credits, pastElections, 0);
    }
    var fs = fsOpt!;
    var pe: PastElection = PastElection.fromSlice(fs, { assertEndAfterReading: true });
    var result = pe.bonuses > 0
         ? unfreezeWithBonuses(credits, pe.frozenDict, pe.totalStake, pe.bonuses)
         : unfreezeWithoutBonuses(credits, pe.frozenDict, pe.totalStake);
    return (result.credits, pastElections, result.recovered);
}

// Config set confirmed
fun configSetConfirmed(sAddr: address, cs: slice, queryId: int, success: bool) {
    val (srcWc, srcAddr) = sAddr.getWorkchainAndHash();
    val configAddr = blockchain.configParam(0)!.beginParse().preloadUint(256);
    var ds = contract.getData().beginParse();
    var electionDict = ds.loadDict();
    if ((srcWc + 1) != BASECHAIN || (srcAddr != configAddr) || electionDict == null) {
        return;
    }
    var election = Election.fromCell(electionDict!, { assertEndAfterReading: true });
    if ((election.electAt != queryId) || !election.finished) {
        //TODO: double check this condition
        // not these elections, or elections not finished yet
        return;
    }

    acceptExternalMessage();

    if (!success) {
        // cancel elections, return stakes
        val (credits, pastElections, grams) = (ds.loadDict(), ds.loadDict(), ds.loadCoins());
        val (newCredits, newPastElections, unusedPrizes) = unfreezeAll(
            credits,
            pastElections,
            election.electAt
        );
        contract.setData(beginCell().storeInt(0, 1).storeDict(newCredits).storeDict(newPastElections)
            .storeCoins(grams + unusedPrizes)
            .storeSlice(ds)
            .endCell());
    }// ... do not remove elect until we see this set as the next elected validator set
}

// Recover stake
fun recoverStake(op: int, sAddr: address, cs: slice, queryId: int) {
    var (srcWc, srcAddr) = sAddr.getWorkchainAndHash();
    if ((srcWc + 1) != 0) {
        // not from masterchain, return error
        sendMessageBack(
            sAddr,
            0xfffffffe,
            queryId,
            op,
            0,
            SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE
        );
        return;
    }
    var ds = contract.getData().beginParse();
    var (elect, credits) = (ds.loadDict(), ds.loadDict());
    var (dataCs, found) = credits.uDictDeleteAndGet(256, srcAddr);
    if (!found) {
        // no credit for sender, return error
        sendMessageBack(
            sAddr,
            0xfffffffe,
            queryId,
            op,
            0,
            SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE
        );
        return;
    }
    var amount = dataCs!.loadCoins();
    dataCs!.assertEnd();
    // save data
    contract.setData(beginCell().storeDict(elect).storeDict(credits).storeSlice(ds).endCell());
    // send amount to sender in a new message
    val reply = createMessage({
        bounce: true,
        value: amount,
        dest: sAddr,
        body: (0xf96f7324 as uint64, queryId as uint32),
    });

    reply.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}


fun afterCodeUpgrade(sAddr: address, cs: slice, queryId: int) {
    sendMessageBack(sAddr, 0xce436f64, queryId, upgradeCodeMessageTag, 0, 64);
}

fun upgradeCode(sAddr: address, cs: slice, queryId: int): bool {
    val cAddr = blockchain.configParam(0);
    if (cAddr == null) {
        return false;
    }

    val configAddr = cAddr!.beginParse().preloadUint(256);
    val (srcWc, srcAddr) = sAddr.getWorkchainAndHash();

    if ((srcWc + 1) != BASECHAIN || (srcAddr != configAddr)) {
        return false;
    }

    acceptExternalMessage();
    val code = cs.loadRef();
    contract.setCodePostponed(code);

    if (!cs.isEmpty()) {
        setTvmRegisterC3(transformSliceToContinuation(code.beginParse()));
        afterCodeUpgrade(sAddr, cs, queryId);
        throw 0;
    }

    return true;
}


fun registerComplaint(sAddr: address, complaint: slice, msgValue: coins): int {
   var (srcWc, srcAddr) = sAddr.getWorkchainAndHash();
    if ((srcWc + 1) != BASECHAIN) {
        return -1;
    }

    if (complaint.depth() >= 128) {
        return -3;
    }

    var data = Storage.load();
    var electionId = complaint.loadUint(32);
    var (fs, found) = data.pastElections.uDictGet(32, electionId);
    if (!found) {
        return -2;
    }

    fs = fs!;
    var expireIn = fs.preloadUint(32) - blockchain.now();
    if (expireIn <= 0) {
        return -4;
    }


    var vc = ValidatorComplaint.fromSlice(complaint, {assertEndAfterReading: true});
    vc.rewardAddr = srcAddr;
    vc.createdAt = blockchain.now();

    val pricing = ComplaintPricing.load();
    val (_, bits, refs) = complaint.calculateSizeStrict(4096);
    val pps = (bits + 1024) * pricing.bitPrice + (refs + 2) * pricing.cellPrice;
    vc.paid = pps * expireIn + pricing.deposit;

    if (msgValue < vc.paid + ton("1")) {
        return -5;
    }


    // Используем автоматический парсинг PastElection
    val newComplaint = vc.toBuilder().endCell() as Cell<ValidatorComplaint>;
    var pe = PastElection.fromSlice(fs, { assertEndAfterReading: true });
    val (validatorFsOpt, validatorFound) = pe.frozenDict.uDictGet(256, vc.validatorPubkey);
    if (!validatorFound) {
        return -6;
    }

    var validatorFs = validatorFsOpt!;
    validatorFs.skipBits(256 + 64);
    val validatorStake = validatorFs.loadCoins();
    val fine = vc.suggestedFine + coinsMuldiv(validatorStake, vc.suggestedFinePart, 1 << 32);

    if (fine > validatorStake) {
        return -7;
    }

    if (fine <= vc.paid) {
        return -8;
    }

    // Создаем статус жалобы
    val cstatus = ComplaintStatus {
        complaint: newComplaint,
        voters: createEmptyDict(),
        vsetId: 0,
        weightRemaining: 0,
    };

    val complaintId = newComplaint.hash();
    val packResult = pe.complaints.uDictSetBuilderIfNotExists(256, complaintId,
        beginCell().storeAny(cstatus)
        );

    if (!packResult) {
        return -9;
    }

    // Сохраняем обновленную информацию
    data.pastElections.uDictSetBuilder(32, electionId, beginCell().storeAny(pe));
    data.save();

    return vc.paid;
}


fun punish(credits: dict, frozen: dict, complaint: cell): PunishResult {
    var vc = ValidatorComplaint.fromSlice(complaint.beginParse(), { assertEndAfterReading: true });
    val (csOpt, found) = frozen.uDictGet(256, vc.validatorPubkey);
    if (!found) {
        // no validator to punish
        return PunishResult {
            credits,
            frozen,
            fineUnalloc: 0,
            fineCollected: 0,
        };
    }
    var cs = csOpt!;
    val addr = cs.loadUint(256);
    val weight = cs.loadUint(64);
    var stake = cs.loadCoins();
    val banned = cs.loadInt(1);

    cs.assertEnd();

    val fine = coinsMin(stake, vc.suggestedFine + coinsMuldiv(stake, vc.suggestedFinePart, 1 << 32));
    stake -= fine;
    frozen.uDictSetBuilder(
        256,
        vc.validatorPubkey,
        beginCell().storeUint(addr, 256).storeUint(weight, 64).storeCoins(stake).storeInt(banned, 1)
    );
    val reward = coinsMin(fine >> 3, vc.paid * 8);
    val newCredits = creditTo(credits, vc.rewardAddr, reward);
    return PunishResult {
        credits: newCredits,
        frozen: frozen,
        fineUnalloc: fine - reward,
        fineCollected: fine,
    };
}

fun registerVote(complaints: dict, hash: int, idx: int, weight: int): (dict, cell?, int) {
    val (cStatusOpt, found) = complaints.uDictGet(256, hash);
    if (!found) {
        // complaint not found
        return (complaints, null, -1);
    }
    val cStatus = cStatusOpt!;
    val currentVset = CurrentVset.load();
    val curVsetId = currentVset.vset.hash();
    var cs = ComplaintStatus.fromSlice(cStatus, {assertEndAfterReading: true});
    var vsetOld = (cs.vsetId != curVsetId);

    if ((cs.weightRemaining < 0) & vsetOld) {
        // previous validator set already collected 2/3 votes, skip new votes
        return (complaints, null, -3);
    }
    if (vsetOld) {
        // complaint votes belong to a previous validator set, reset voting
        cs.vsetId = curVsetId;
        cs.voters = createEmptyDict();
        cs.weightRemaining = intMuldiv(currentVset.totalWeight, 2, 3);
    }
    var (_, voteFound) = cs.voters.uDictGet(16, idx);
    if (voteFound) {
        // already voted for this proposal, ignore vote
        return (complaints, null, 0);
    }
    // register vote
    cs.voters.uDictSetBuilder(16, idx, beginCell().storeUint(blockchain.now(), 32));
    var oldWr = cs.weightRemaining;
    cs.weightRemaining -= weight;
    oldWr ^= cs.weightRemaining;
    // save voters and weightRemaining
    complaints.uDictSetBuilder(256, hash, ComplaintStatus.toBuilder(cs));
    if (oldWr >= 0) {
        // not enough votes or already accepted
        return (complaints, null, 1);
    }
    // complaint wins, prepare punishment
    return (complaints, cs.complaint, 2);
}

fun proceedRegisterVote(electionId: int, hash: int, idx: int, weight: int): int {
    var data = Storage.load();
    val (fsOpt, found) = data.pastElections
    .uDictGet(32, electionId);
    if (!found) {
        // election not found
        return -2;
    }
    val fs = fsOpt!;
    var pe = PastElection.fromSlice(fs, {assertEndAfterReading: true});
    var (newComplaints, acceptedComplaint, status) = registerVote(pe.complaints, hash, idx, weight);
    if (status <= 0) {
        return status;
    }
    pe.complaints = newComplaints;
    if (acceptedComplaint != null) {
        val punishResult = punish(
            data.credits,
            pe.frozenDict,
            acceptedComplaint
        );
        data.credits = punishResult.credits;
        pe.frozenDict = punishResult.frozen;
        data.grams += punishResult.fineUnalloc;
        pe.totalStake -= punishResult.fineCollected;
    }
    data.pastElections.uDictSetBuilder(32, electionId, pe.toBuilder());
    data.save();
    return status;
}

// Tick-tock implementation
fun onRunTickTock(isTock: bool) {
    // check whether an election is being conducted
    var ds = contract.getData().beginParse();
    val (elect, credits) = (ds.loadDict(), ds.loadDict());
    if (elect != null) {
        // have an active election
        if (conductElections(ds, elect, credits)) {
            return; // elections conducted, exit
        }
        if (validatorSetInstalled(ds, elect, credits)) {
            return; // validator set installed, current elections removed
        }
    } else {
        if (announceNewElections(ds, elect, credits)) {
            return; // new elections announced, exit
        }
    }
    val updateResult = updateActiveVsetId();
    if (updateResult) {
        return; // active validator set id updated, exit
    }

    checkUnfreeze();
}

fun postponeElections(): bool {
    return false;
}

// computes the total stake out of the first n entries of list l
fun computeTotalStake(l: tuple, n: int, mStake: coins): coins {
    var totStake: coins = 0;
    var currentList = l;
    repeat (n) {
        var (head, newList) = listSplit<tuple>(currentList);
        currentList = newList!; //TODO: double check
        var stake = head.get<coins>(0);
        var maxF = head.get<int>(1);
        stake = coinsMin(stake, (maxF * mStake) >> 16);
        totStake += stake;
    }
    return totStake;
}

fun tryElect(
    credits: dict,
    members: dict,
    minStake: coins,
    maxStake: coins,
    minTotalStake: coins,
    maxStakeFactor: int,
): (dict, dict, int, dict, coins, int) {
    var cs = blockchain.configParam(16)!.beginParse();
    var (maxValidators, _, minValidators) = (cs.loadUint(16), cs.loadUint(16), cs.loadUint(16));
    cs.assertEnd();

    minValidators = intMax(minValidators, 1);
    var n = 0;
    var sdict = createEmptyDict();
    var pubkey = -1;
    do {
        var (nextKeyOpt, memberCsOpt, found) = members.uDictGetNext(256, pubkey);
        if (found) {
            pubkey = nextKeyOpt!;
            var memberCs = memberCsOpt!;

            val stake = memberCs.loadCoins();
            val time = memberCs.loadUint(32);
            val maxFactor = memberCs.loadUint(32);
            val addr = memberCs.loadUint(256);
            val adnlAddr = memberCs.loadUint(256);
            memberCs.assertEnd();

            val key = beginCell().storeUint(stake, 128).storeInt(-time, 32) //what
                .storeUint(pubkey, 256)
                .endCell()
                .beginParse();
            sdict.sDictSetBuilder(
                128 + 32 + 256,
                key,
                beginCell()
                .storeUint(intMin(maxFactor, maxStakeFactor), 32).storeUint(addr, 256)
                .storeUint(adnlAddr, 256)
            );
            n += 1;
        }
    } while (found);
    n = intMin(n, maxValidators);
    if (n < minValidators) {
        return (credits, createEmptyDict(), 0, createEmptyDict(), 0, 0);
    }
    var l = createEmptyList();

    do {
        var (keyOpt, validatorCsOpt, found) = sdict.sDictDeleteFirstAndGet(128 + 32 + 256);
        if (found) {
            var key = keyOpt!;
            var validatorCs = validatorCsOpt!;

            val stake = coinsMin(key.loadUint(128), maxStake);
            key.loadUint(32); // skip time
            val pubkey = key.preloadUint(256);

            val maxF = validatorCs.loadUint(32);
            validatorCs.loadUint(256); // skip addr
            val adnlAddr = validatorCs.preloadUint(256);

            val head = [stake, maxF, pubkey, adnlAddr] as tuple; //TODO: safe?
            l = listPrepend(head, l);
        }
    } while (found);
    // l is the list of all stakes in decreasing order
    var i = minValidators - 1;
    var l1 = l;
    repeat (i) {
        l1 = listGetTail(l1)!; //TODO: double check this !
    }

    var (bestStake, m) = (0, 0);
    do {
        val (head: tuple, newList) = listSplit(l1);
        l1 = newList!; //todo: double check this
        var stake = head.get<coins>(0);
        i += 1;
        if (stake >= minStake) {
            val totStake = computeTotalStake(l, i, stake);
            if (totStake > bestStake) {
                (bestStake, m) = (totStake, i);
            }
        }
    } while (i < n);

    if ((m == 0) || (bestStake < minTotalStake)) {
        return (credits, createEmptyDict(), 0, createEmptyDict(), 0, 0);
    }
    // we have to select first m validators from list l
    l.stackMoveToTop();
    l1 = l;

    repeat (m - 1) {
        l1 = listGetTail(l1)!; //todo: double check this
    }

    val head = listGetHead<tuple>(l1); //todo: not sure. need to test
    val mStake = head.get<coins>(0);

    // create both the new validator set and the refund set
    i = 0; //reset counter
    var totStake: coins = 0;
    var totWeight = 0;
    var vset = createEmptyDict();
    var frozen = createEmptyDict();
    var currentList: tuple? = l;
    do {
        val (validatorData: tuple, newList) = listSplit(currentList);
        currentList = newList;
        //var (stake: coins, maxF, pubkey, adnlAddr) = validatorData;
        var stake = validatorData.get<coins>(0);
        val maxF = validatorData.get<int>(1);
        val pubkey = validatorData.get<uint256>(2);
        val adnlAddr = validatorData.get<uint256>(3);
        // lookup source address first
        var (valueOpt, validatorExists) = members.uDictGet(256, pubkey);
        assert(validatorExists, 61);
        var value = valueOpt!;

        value.loadCoins(); // skip stake
        value.skipBits(64); // skip time and maxFactor
        val srcAddr = value.preloadUint(256);

        if (i < m) {
            // one of the first m members, include into validator set
            var trueStake = coinsMin(stake, (maxF * mStake) >> 16);
            stake -= trueStake;
            // ed25519_pubkey#8e81278a pubkey:bits256 = SigPubKey;  // 288 bits
            // validator_addr#73 public_key:SigPubKey weight:uint64 adnl_addr:bits256 = ValidatorDescr;
            var weight = (trueStake << 60) / bestStake;
            totStake += trueStake;
            totWeight += weight;

            var vInfo = beginCell().storeUint(adnlAddr != 0 ? 0x73 : 0x53, 8) // validator_addr#73 or validator#53
                .storeUint(0x8e81278a, 32) // ed25519_pubkey#8e81278a
                .storeUint(pubkey, 256) // pubkey:bits256
                .storeUint(weight, 64); // weight:uint64

            if (adnlAddr != 0) {
                vInfo = vInfo.storeUint(adnlAddr, 256); // adnl_addr:bits256
            }
            vset.uDictSetBuilder(16, i, vInfo);
            frozen.uDictSetBuilder(
                256,
                pubkey,
                beginCell()
                    .storeUint(srcAddr, 256).storeUint(weight, 64).storeCoins(trueStake)
                    .storeBool(true)
            );
        }
        if (stake != 0) {
            // non-zero unused part of the stake, credit to the source address
            credits = creditTo(credits, srcAddr, stake);
        }
        i += 1;
    } while (currentList != null);
    assert(totStake == bestStake, 49);
    return (credits, vset, totWeight, frozen, totStake, m);
}

fun conductElections(ds: slice, elect: cell, credits: dict): bool {
    var election = Election.fromCell(elect, { assertEndAfterReading: true });
    if (blockchain.now() < election.electClose) {
        // elections not finished yet
        return false;
    }
    if (blockchain.configParam(0) == null) {
        // no configuration smart contract to send result to
        return postponeElections();
    }

    var cs = blockchain.configParam(17)!.beginParse();
    var minStake = cs.loadCoins();
    var maxStake = cs.loadCoins();
    var minTotalStake = cs.loadCoins();
    var maxStakeFactor = cs.loadUint(32);
    cs.assertEnd();

    if (election.totalStake < minTotalStake) {
        // insufficient total stake, postpone elections
        return postponeElections();
    }
    if (election.failed) {
        // do not retry failed elections until new stakes arrive
        return postponeElections();
    }
    if (election.finished) {
        // elections finished
        return false;
    }
    var (newCredits, vdict, totalWeight, frozen, totalStakes, cnt) = tryElect(
        credits,
        election.members,
        minStake,
        maxStake,
        minTotalStake,
        maxStakeFactor
    );
    // pack elections; if cnt==0, set failed=true, finished=false.
    var failed = (cnt == 0);
    var finished = !failed;
    elect = Election {
        electAt: election.electAt,
        electClose: election.electClose,
        minStake: minStake,
        totalStake: election.totalStake,
        members: election.members,
        failed: failed,
        finished: finished,
    }.toCell();

    if (cnt == 0) {
        // elections failed, set elect_failed to true
        contract.setData(beginCell().storeDict(elect).storeDict(newCredits).storeSlice(ds).endCell());
        return postponeElections();
    }
    // serialize a query to the configuration smart contract
    // to install the computed validator set as the next validator set
    var validatorConfig = ValidatorConfig.load();
    var start = intMax(blockchain.now() + validatorConfig.electionsEndBefore - 60, election.electAt);
    var mainValidators = blockchain.configParam(16)!.beginParse().skipBits(16).preloadUint(16);
    var vset = beginCell().storeUint(0x12, 8) // validators_ext#12
        .storeUint(start, 32) // utime_since:uint32
        .storeUint(start + validatorConfig.electedFor, 32) // utime_until:uint32
        .storeUint(cnt, 16) // total:(## 16)
        .storeUint(intMin(cnt, mainValidators), 16) // main:(## 16)
        .storeUint(totalWeight, 64) // total_weight:uint64
        .storeDict(vdict) // list:(HashmapE 16 ValidatorDescr)
        .endCell();
    var configAddr = blockchain.configParam(0)!.beginParse().preloadUint(256);
    sendValidatorSetToConfig(configAddr, vset, election.electAt);
    // add frozen to the dictionary of past elections
    var pastElectionsDict = ds.loadDict();

    val electionsBuilder = PastElection {
            unfreezeAt: start + validatorConfig.electedFor + validatorConfig.stakeHeldFor,
            stakeHeld: validatorConfig.stakeHeldFor as uint32, //TODO: found incosistency in original func
            vsetHash: vset.hash(),
            frozenDict: frozen,
            totalStake: totalStakes,
            bonuses: 0,
            complaints: createEmptyDict(),
    }.toBuilder();

    pastElectionsDict.uDictSetBuilder(
        32,
        election.electAt,
        electionsBuilder
    );
    // store credits and frozen until end
    contract.setData(
        beginCell()
        .storeDict(elect)
        .storeDict(newCredits)
        .storeDict(pastElectionsDict)
        .storeSlice(ds)
        .endCell());
    return true;
}

fun updateActiveVsetId(): bool {
    var data = Storage.load();
    val curHash = blockchain.configParam(34)!.hash();
    if (curHash == data.activeHash) {
        // validator set unchanged
        return false;
    }
    if (data.activeId != 0) {
        // activeId becomes inactive
        val (fsOpt, found) = data.pastElections.uDictGet(32, data.activeId);
        if (found) {
            var fs = fsOpt!;

            // adjust unfreeze time of this validator set
            var unfreezeTime = fs.loadUint(32);
            var fs0 = fs; //todo: is it cloning?

            val (stakeHeld, hash) = (fs.loadUint(32), fs.loadUint(256));
            assert(hash == data.activeHash, 57);
            unfreezeTime = blockchain.now() + stakeHeld;
            data.pastElections.uDictSetBuilder(
                32,
                data.activeId,
                beginCell().storeUint(unfreezeTime, 32).storeSlice(fs0)
            );
        }
    }
    // look up new activeId by hash
    var id = -1;
    do {
        var (nextKeyOpt, fsOpt, found) = data.pastElections.uDictGetNext(32, id);
        if (found) {
            id = nextKeyOpt!;
            var fs = fsOpt!;
            var tm = fs.skipBits(32).loadUint(32);
            var hash = fs.loadUint(256);
            if (hash == curHash) {
                // parse more of this record
                var (dict, totalStake, bonuses) = (fs.loadDict(), fs.loadCoins(), fs.loadCoins());
                // transfer 1/8 of accumulated everybody's grams to this validator set as bonuses
                var amount = (data.grams >> 3);
                data.grams -= amount;
                bonuses += amount;
                // serialize back
                data.pastElections.uDictSetBuilder(
                    32,
                    id,
                    beginCell().storeUint(tm, 64).storeUint(hash, 256).storeDict(dict).storeCoins(totalStake)
                        .storeCoins(bonuses)
                        .storeSlice(fs)
                );

                found = false;
            }
        }
    } while (found);

    data.activeId = id == -1 ? 0 : id;
    data.activeHash = curHash;
    data.save();
    return true;
}



fun validatorSetInstalled(ds: slice, elect: cell, credits: dict): bool {
    val election = Election.fromCell(elect, { assertEndAfterReading: true });
    if (!election.finished) {
        // elections not finished yet
        return false;
    }
    val pastElections = ds.loadDict();
    val (fsOpt, found) = pastElections.uDictGet(32, election.electAt);
    if (!found) {
        // no election data in dictionary
        return false;
    }
    var fs = fsOpt!;
    // recover validator set hash
    val vsetHash = fs.skipBits(64).preloadUint(256);
    if (
        cellHashEq(blockchain.configParam(34), vsetHash) |
        cellHashEq(blockchain.configParam(36), vsetHash)
    ) {
        // this validator set has been installed, forget elections
        contract.setData(
            beginCell()
            .storeBool(false) // forget current elections
            .storeDict(credits)
            .storeDict(pastElections)
            .storeSlice(ds)
            .endCell());
        updateActiveVsetId();
        return true;
    }
    return false;
}

fun checkUnfreeze(): bool {
    var data = Storage.load();
    var id = -1;
    do {
        var (nextKeyOpt, fsOpt, found) = data.pastElections.uDictGetNext(32, id);
        if (found) {
            id = nextKeyOpt!;
            var fs = fsOpt!;
            var unfreezeAt = fs.loadUint(32);
            if ((unfreezeAt <= blockchain.now()) & (id != data.activeId)) {
                // unfreeze!
                var (newCredits, newPastElections, unusedPrizes) = unfreezeAll(
                    data.credits,
                    data.pastElections,
                    id
                );
                data.credits = newCredits;
                data.pastElections = newPastElections;
                data.grams += unusedPrizes;
                // unfreeze only one at time, exit loop
                data.save();
                // exit loop
                found = false;
            }
        }
    } while (found);
    return id != -1;
}

fun announceNewElections(ds: slice, elect: dict?, credits: dict): bool {
    var nextVset = blockchain.configParam(36); // next validator set
    if (nextVset != null) {
        // next validator set exists, no elections needed
        return false;
    }
    var electorAddr = blockchain.configParam(1)!.beginParse().preloadUint(256);
    var (myWc, myAddr) = contract.getAddress().getWorkchainAndHash();
    if ((myWc + 1) != BASECHAIN || (myAddr != electorAddr)) {
        // this smart contract is not the elections smart contract anymore, no new elections
        return false;
    }
    var curVset = blockchain.configParam(34); // current validator set
    if (curVset == null) {
        return false;
    }
    curVset = curVset!;

    val validatorConfig = ValidatorConfig.load();
    val curValidUntil = curVset.beginParse().skipBits(8 + 32).preloadUint(32);
    var t = blockchain.now();
    val t0 = curValidUntil - validatorConfig.electionsBeginBefore;
    if (t < t0) {
        // too early for the next elections
        return false;
    }
    // less than elect_before_begin seconds left, create new elections
    if (t - t0 < 60) {
        // pretend that the elections started at t0
        t = t0;
    }
    // get stake parameters
    val minStake = blockchain.configParam(17)!.beginParse().loadCoins();
    // announce new elections
    val electAt = t + validatorConfig.electionsBeginBefore;
    val electClose = electAt - validatorConfig.electionsEndBefore;
    elect = Election {
        electAt: electAt,
        electClose: electClose,
        minStake: minStake,
        totalStake: 0,
        members: createEmptyDict(),
        failed: false,
        finished: false,
    }.toCell();
    contract.setData(beginCell().storeDict(elect).storeDict(credits).storeSlice(ds).endCell());
    return true;
}


// Main message handler
fun onInternalMessage(msgValue: coins, inMsgCell: cell, inMsgBody: slice) {
    var cs = inMsgCell.beginParse();
    val flags = cs.loadUint(4); // int_msg_info$0 ihr_disabled:Bool bounce:Bool bounced:Bool
    if (flags & 1) {
        // ignore all bounced messages
        return;
    }
    val sAddr = cs.loadAddress();
    if (inMsgBody.isEmpty()) {
        // inbound message has empty body
        processSimpleTransfer(sAddr, msgValue);
        return;
    }
    val op = inMsgBody.loadUint(32);
    if (op == 0) {
        // simple transfer with comment, return
        processSimpleTransfer(sAddr, msgValue);
        return;
    }
    val queryId = inMsgBody.loadUint(64);
    if (op == newStakeMessageTag) {
        // new stake message
        processNewStake(sAddr, msgValue, inMsgBody, queryId);
        return;
    }
    if (op == recoverStakeMessageTag) {
        // recover stake request
        recoverStake(op, sAddr, inMsgBody, queryId);
        return;
    }
    if (op == upgradeCodeMessageTag) {
        // upgrade code (accepted only from configuration smart contract)
        val ok = upgradeCode(sAddr, inMsgBody, queryId);
        sendMessageBack(sAddr, ok ? 0xce436f64 : 0xffffffff, queryId, op, 0, 64);
        return;
    }
    var cfgOk = (op == 0xee764f4b);
    if (cfgOk || (op == 0xee764f6f)) {
        // confirmation from configuration smart contract
        configSetConfirmed(sAddr, inMsgBody, queryId, cfgOk);
        return;
    }
    if (op == newComplaintMessageTag) {
        // new complaint
        val price = registerComplaint(sAddr, inMsgBody, msgValue);
        var mode = 64;
        var ansTag = -price;
        if (price >= 0) {
            // ok, debit price
            reserveToncoinsOnBalance(price, RESERVE_MODE_INCREASE_BY_ORIGINAL_BALANCE);
            ansTag = 0;
            mode = 128;
        }
        sendMessageBack(sAddr, ansTag + 0xf2676350, queryId, op, 0, mode);
        return;
    }
    if (op == voteForComplaintMessageTag) {
        // vote for a complaint
        val signature = inMsgBody.loadBits(512);
        val msgBody = inMsgBody;
        val (signTag, validatorIdx, electionId, hash) = (
            inMsgBody.loadUint(32),
            inMsgBody.loadUint(16),
            inMsgBody.loadUint(32),
            inMsgBody.loadUint(256)
        );
        inMsgBody.assertEnd();

        assert(signTag == 0x56744350, 37);
        val currentVset = CurrentVset.load();
        val description = currentVset.getDescr(validatorIdx);
        assert(description.value != null, 34);
        val validatorInfo = ValidatorDescr.loadValidatorInfo(description.value);
        assert(isSliceSignatureValid(msgBody, signature, validatorInfo.pubkey), 34);
        val res = proceedRegisterVote(electionId, hash, validatorIdx, validatorInfo.weight);
        sendMessageBack(
            sAddr,
            res + 0xd6745240,
            queryId,
            op,
            0,
            SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE
        );
        return;
    }

    if (!(op & (1 << 31))) {
        // unknown query, return error
        sendMessageBack(
            sAddr,
            0xffffffff,
            queryId,
            op,
            0,
            SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE
        );
        return;
    }
}

// Helper functions
fun coinsMin(a: coins, b: coins): coins {
    return a < b ? a : b;
}

fun intMin(a: int, b: int): int {
    return a < b ? a : b;
}

fun intMax(a: int, b: int): int {
    return a > b ? a : b;
}

fun intMuldiv(a: int, b: int, c: int): int {
    return (a * b) / c;
}

fun coinsMuldiv(a: coins, b: int, c: int): coins {
    return (a * b) / c;
}

fun cellHashEq(vset: cell?, expectedVsetHash: int): bool {
    return vset == null ? false : vset.hash() == expectedVsetHash;
}

// Get methods
get fun activeElectionId(): int {
    val elect = contract.getData().beginParse().preloadDict();
    return elect == null ? 0 : elect!.beginParse().preloadUint(32);
}

// checks whether a public key participates in current elections
get fun participatesIn(validatorPubkey: int): coins {
    val elect = contract.getData().beginParse().preloadDict();
    if (elect == null) {
        return 0;
    }
    val election = Election.fromCell(elect, {assertEndAfterReading: true});
    var (mem, found) = election.members.uDictGet(256, validatorPubkey);
    return found ? mem!.loadCoins() : 0;
}

// returns the list of all participants of current elections with their stakes
get fun participantList(): tuple {
    val elect = contract.getData().beginParse().preloadDict();
    if (elect == null) {
        return createEmptyTuple();
    }
    val election = Election.fromCell(elect, {assertEndAfterReading: true});
    var l = createEmptyTuple();
    var id = (1 << 255) + ((1 << 255) - 1);
    do {
        val (nextKey, fsOpt, f) = election.members.uDictGetPrev(256, id);
        if (f) {
            id = nextKey!;
            var fs = fsOpt!;

            val head = [id, fs.loadCoins()] as tuple;
            l = listPrepend(head, l);
        }
    } while (f);
    return l;
}


fun ExtendedParticipationList.empty(): ExtendedParticipationList {
    return ExtendedParticipationList {
        electAt: 0,
        electClose: 0,
        minStake: 0,
        totalStake: 0,
        participants: createEmptyTuple(),
        failed: false,
        finished: false
    }
}

// returns the list of all participants of current elections with their data
get fun participantListExtended(): ExtendedParticipationList {
    var elect = contract.getData().beginParse().preloadDict();
    if (elect == null) {
        return ExtendedParticipationList.empty();
    }
    val election = Election.fromCell(elect);
    var l = createEmptyTuple();
    var id = (1 << 255) + ((1 << 255) - 1);
    do {
        var (nextKey, cs, found) = election.members.uDictGetPrev(256, id);
        if (found) {
            id = nextKey!;
            cs = cs!;
            val stake = cs.loadCoins();
            val _ = cs.loadInt(32); //skip time
            val maxFactor = cs.loadUint(32);
            val addr = cs.loadUint(256);
            val adnlAddr = cs.loadUint(256);
            cs.assertEnd();

            val head = [id, [stake, maxFactor, addr, adnlAddr]] as tuple;

            l = listPrepend(head, l);
        }
    } while (found);
    return ExtendedParticipationList {
        electAt: election.electAt,
        electClose: election.electClose,
        minStake: election.minStake,
        totalStake: election.totalStake,
        participants: l,
        failed: election.failed,
        finished: election.finished
    };
}

// computes the return stake
get fun computeReturnedStake(walletAddr: int): coins {
    var cs = contract.getData().beginParse();
    val (_, credits) = (cs.loadDict(), cs.loadDict());
    var (valueOpt, found) = credits.uDictGet(256, walletAddr);
    return found ? valueOpt!.loadCoins() : 0;
}

// returns the list of past election ids
get fun pastElectionIds(): tuple {
    var data = Storage.load();
    var id = (1 << 32);
    var list = createEmptyTuple(); //TODO: nil from func? safe?
    do {
        var (nextKey, fsOpt, found) = data.pastElections.uDictGetPrev(32, id);
        if (found) {
            id = nextKey!;
            list = listPrepend(id, list);
        }
    } while (found);
    return list;
}

get fun complaintStoragePrice(bits: int, refs: int, expireIn: int): coins {
    // compute complaint storage/creation price
    val pricing = ComplaintPricing.load();
    val pps = (bits + 1024) * pricing.bitPrice + (refs + 2) * pricing.cellPrice;
    val paid = pps * expireIn + pricing.deposit;
    return paid + ton("1");
}
