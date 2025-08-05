tolk 1.0

import "@stdlib/tvm-dicts"
import "@stdlib/tvm-lowlevel"
import "@stdlib/lisp-lists"
import "@stdlib/gas-payments"


struct ElectorData {
    curElect: dict
    credits: dict
    pastElections: dict
    grams: coins
    activeId: uint32
    activeHash: uint256
}

fun loadContractData(): ElectorData {
    var cs = contract.getData().beginParse();
    return ElectorData {
        curElect: cs.loadDict(),
        credits: cs.loadDict(),
        pastElections: cs.loadDict(),
        grams: cs.loadCoins(),
        activeId: cs.loadUint(32),
        activeHash: cs.loadUint(256),
    };
}

fun storeContractData(data: ElectorData) {
    contract.setData(
            beginCell()
            .storeDict(data.curElect)
            .storeDict(data.credits)
            .storeDict(
                data
                .pastElections)
                .storeCoins(data.grams)
                .storeUint(data.activeId, 32)
                .storeUint(data.activeHash, 256)
                .endCell()
            );
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

fun unpackElect(election_cell: cell): Election {
    var es = election_cell.beginParse();
    val election = Election {
        electAt: es.loadUint(32),
        electClose: es.loadUint(32),
        minStake: es.loadCoins(),
        totalStake: es.loadCoins(),
        members: es.loadDict(),
        failed: es.loadInt(1) != 0,
        finished: es.loadInt(1) != 0,
    };
    es.assertEnd();
    return election;
}

fun packElect(election: Election): cell {
    return beginCell()
        .storeUint(election.electAt, 32)
        .storeUint(election.electClose, 32)
        .storeCoins(election.minStake)
        .storeCoins(election.totalStake)
        .storeDict(election.members)
        .storeInt(election.failed ? -1 : 0, 1)
        .storeInt(election.finished ? -1 : 0, 1)
        .endCell();
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

fun unpackPastElection(fs: slice): PastElection {
    val election = PastElection {
        unfreezeAt: fs.loadUint(32),
        stakeHeld: fs.loadUint(32),
        vsetHash: fs.loadUint(256),
        frozenDict: fs.loadDict(),
        totalStake: fs.loadCoins(),
        bonuses: fs.loadCoins(),
        complaints: fs.loadDict(),
    };

    fs.assertEnd();
    return election;
}

fun packPastElection(pe: PastElection): builder {
    return beginCell()
        .storeUint(pe.unfreezeAt, 32)
        .storeUint(pe.stakeHeld, 32)
        .storeUint(pe.vsetHash,256)
        .storeDict(pe.frozenDict)
        .storeCoins(pe.totalStake)
        .storeCoins(pe.bonuses)
        .storeDict(pe.complaints);
}


struct ComplaintStatus {
    complaint: cell
    voters: dict
    vsetId: uint256
    weightRemaining: int64
}

fun unpackComplaintStatus(cs: slice): ComplaintStatus {
    assert(cs.loadUint(8) == 0x2d, 9);
    val status = ComplaintStatus {
        complaint: cs.loadRef(),
        voters: cs.loadDict(),
        vsetId: cs.loadUint(256),
        weightRemaining: cs.loadInt(64),
    };
    cs.assertEnd();
    return status;
}

fun packComplaintStatus(cs: ComplaintStatus): builder {
    return beginCell()
    .storeUint(0x2d, 8)
    .storeRef(cs.complaint)
    .storeDict(cs.voters)
    .storeUint(cs.vsetId,256)
    .storeInt(cs.weightRemaining, 64);
}


struct ValidatorComplaint {
    validatorPubkey: uint256
    description: cell
    createdAt: uint32
    severity: uint8
    rewardAddr: uint256
    paid: coins
    suggestedFine: coins
    suggestedFinePart: uint32
}

fun unpackComplaint(cs: slice): ValidatorComplaint {
    assert(cs.loadInt(8) == 0xbc - 0x100, 9);
    val vc = ValidatorComplaint {
        validatorPubkey: cs.loadUint(256),
        description: cs.loadRef(),
        createdAt: cs.loadUint(32),
        severity: cs.loadUint(8),
        rewardAddr: cs.loadUint(256),
        paid: cs.loadCoins(),
        suggestedFine: cs.loadCoins(),
        suggestedFinePart: cs.loadUint(32),
    };
    cs.assertEnd();
    return vc;
}

fun packComplaint(vc: ValidatorComplaint): builder {
    return beginCell().storeInt(0xbc - 0x100, 8)
        .storeUint(vc.validatorPubkey, 256)
        .storeRef(vc.description)
        .storeUint(vc.createdAt, 32)
        .storeUint(vc.severity, 8)
        .storeUint(vc.rewardAddr, 256)
        .storeCoins(vc.paid)
        .storeCoins(vc.suggestedFine)
        .storeUint(vc.suggestedFinePart, 32);
}


struct ComplaintPricing {
    deposit: coins
    bitPrice: coins
    cellPrice: coins
}

fun parseComplaintPrices(info: cell): ComplaintPricing {
    var cs = info.beginParse();
    assert(cs.loadUint(8) == 0x1a, 9);
    val cp = ComplaintPricing {
        deposit: cs.loadCoins(),
        bitPrice: cs.loadCoins(),
        cellPrice: cs.loadCoins(),
    };
    cs.assertEnd();
    return cp;
}

fun getComplaintPrices(): ComplaintPricing {
    var info = blockchain.configParam(13);
    if (info == null) {
        return ComplaintPricing {
            deposit: ton("0") + (1 << 36),
            bitPrice: ton("0") + 1,
            cellPrice: ton("0") + 512,
        };
    }

    return parseComplaintPrices(info);
}


struct ValidatorConf {
    electedFor: int32
    electionsBeginBefore: int32
    electionsEndBefore: int32
    stakeHeldFor: int32
}

fun getValidatorConf(): ValidatorConf {
    val cs = blockchain.configParam(15)!.beginParse();

    return ValidatorConf {
        electedFor: cs.loadInt(32),
        electionsBeginBefore: cs.loadInt(32),
        electionsEndBefore: cs.loadInt(32),
        stakeHeldFor: cs.preloadInt(32),
    };
}


struct CurrentVset {
    vset: cell
    totalWeight: uint64
    dict: dict
}

fun getCurrentVset(): CurrentVset {
    val vset = blockchain.configParam(34)!;
    val cs = vset.beginParse();
    // validators_ext#12 utime_since:uint32 utime_until:uint32
    // total:(## 16) main:(## 16) { main <= total } { main >= 1 }
    // total_weight:uint64
    assert(cs.loadUint(8) == 0x12, 40);
    cs.skipBits(32 + 32 + 16 + 16);
    val totalWeight = cs.loadUint(64);
    val dict = cs.loadDict();
    cs.assertEnd();

    return CurrentVset {
        vset,
        totalWeight,
        dict,
    };
}

struct ValidatorDescr {
    value: slice?
    totalWeight: int
}

fun getValidatorDescr(idx: int): ValidatorDescr {
    var vsetInfo = getCurrentVset();
    var (value, found) = vsetInfo.dict.uDictGet(16, idx);
    return ValidatorDescr { value, totalWeight: vsetInfo.totalWeight };
}

struct ValidatorInfo {
    pubkey: uint256
    weight: uint64
}

fun unpackValidatorDescr(cs: slice): ValidatorInfo {
    // ed25519_pubkey#8e81278a pubkey:bits256 = SigPubKey;
    // validator#53 public_key:SigPubKey weight:uint64 = ValidatorDescr;
    // validator_addr#73 public_key:SigPubKey weight:uint64 adnl_addr:bits256 = ValidatorDescr;
    assert((cs.loadUint(8) & ~0x20) == 0x53, 41); //TODO: check this
    assert(cs.loadUint(32) == 0x8e81278a, 41);
    return ValidatorInfo { pubkey: cs.loadUint(256), weight: cs.loadUint(64) };
}

// Message sending functions
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
        ton("0"),
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

// Credit management
fun creditTo(credits: dict, addr: int, amount: coins): dict {
    val (value, found) = credits.uDictGet(256, addr);
    if (found) {
        amount += value!.loadCoins();
    }
    credits.uDictSetBuilder(256, addr, beginCell().storeCoins(amount));
    return credits;
}

// Simple transfer processing
fun processSimpleTransfer(sAddr: address, msgValue: coins) {
    val data = loadContractData();
    val (srcWc, srcAddr) = sAddr.getWorkchainAndHash();
    if (srcAddr != 0 || (srcWc + 1) != 0 || (data.activeId == 0)) {
        //TODO: check
        // simple transfer to us (credit "nobody's" account)
        data.grams += msgValue;
        storeContractData(data);
        return;
    }

    // zero source address -1:00..00 (collecting validator fees)
    val (fs, found) = data.pastElections.uDictGet(32, data.activeId);
    if (!found) {
        // active validator set not found
        data.grams += msgValue;
    } else {
        // credit active validator set bonuses
        val pe = unpackPastElection(fs!);
        pe.bonuses += msgValue;
        data.pastElections.uDictSetBuilder(32, data.activeId, packPastElection(pe));
    }
    storeContractData(data);
}

// New stake processing
fun processNewStake(sAddr: address, msgValue: coins, cs: slice, queryId: int) {
    val (srcWc, srcAddr) = sAddr.getWorkchainAndHash();
    val ds = contract.getData().beginParse();
    val election_dict = ds.loadDict();
    if (election_dict == null || (srcWc + 1) != 0) {
        // no elections active, or source is not in masterchain
        returnStake(sAddr, queryId, 0);
        return;
    }

    // parse the remainder of new stake message
    val validatorPubkey = cs.loadUint(256);
    val stakeAt = cs.loadUint(32);
    val maxFactor = cs.loadUint(32);
    val adnlAddr = cs.loadUint(256);
    val signature = cs.loadRef()
    .beginParse()
    .preloadBits(512);

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
    var election = unpackElect(election_dict!);
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
    assert(msgValue > ton("0"), 44);

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
    val new_elect_dict = packElect(election);
    contract.setData(beginCell().storeDict(new_elect_dict).storeSlice(ds).endCell());
    // return confirmation message
    if (queryId != 0) {
        sendConfirmation(sAddr, queryId, 0);
    }
}

fun unfreezeWithoutBonuses(credits: dict, freezeDict: dict, totStakes: coins): (dict, coins) {
    var new_credits = credits;
    var total = ton("0");
    var recovered = ton("0");
    var pubkey = -1;
    do {
        var (nextKey, cs, found) = freezeDict.uDictGetNext(256, pubkey);
        if (found) {
            pubkey = nextKey!;
            val css = cs!;

            val addr = css.loadUint(256);
            val _weight = css.loadUint(64);
            val stake = css.loadCoins();
            val banned = css.loadInt(1) != 0;
            css.assertEnd();

            if (banned) {
                recovered += stake;
            } else {
                new_credits = creditTo(new_credits, addr, stake);
            }
            total += stake;
        }
    } while (found);
    assert(total == totStakes, 59);
    return (new_credits, recovered);
}

fun unfreezeWithBonuses(credits: dict, freezeDict: dict, totStakes: coins, totBonuses: coins): (dict, coins) {
    var new_credits = credits;
    var total = ton("0");
    var recovered = ton("0");
    var returnedBonuses = ton("0");
    var pubkey = -1;
    do {
        var (nextKey, cs, found) = freezeDict.uDictGetNext(256, pubkey);
        if (found) {
            pubkey = nextKey!;
            cs = cs!;
            val addr = cs.loadUint(256);
            val _ = cs.loadUint(64); //weight
            val stake = cs.loadCoins();
            val banned = cs.loadInt(1) != 0;
            cs.assertEnd();

            if (banned) {
                recovered += stake;
            } else {
                var bonus = muldiv_f(totBonuses, stake, totStakes);
                returnedBonuses += bonus;
                new_credits = creditTo(new_credits, addr, stake + bonus);
            }
            total += stake;
        }
    } while (found);
    assert((total == totStakes) & (returnedBonuses <= totBonuses), 59);
    return (credits, recovered + totBonuses - returnedBonuses);
}

fun unfreezeAll(credits: dict, pastElections: dict, electId: int): (dict, dict, coins) {
    var (fs, found) = pastElections.uDictDeleteAndGet(32, electId);
    if (!found) {
        // no elections with this id
        return (credits, pastElections, ton("0"));
    }
    var pe = unpackPastElection(fs!);
    var unusedPrizes = (pe.bonuses > ton("0"))
         ? unfreezeWithBonuses(credits, pe.frozenDict, pe.totalStake, pe.bonuses).1
         : unfreezeWithoutBonuses(credits, pe.frozenDict, pe.totalStake).1;
    return (credits, pastElections, unusedPrizes);
}

// Config set confirmed
fun configSetConfirmed(sAddr: address, cs: slice, queryId: int, success: bool) {
    var (srcWc, srcAddr) = sAddr.getWorkchainAndHash();
    var configAddr = blockchain.configParam(0)!.beginParse().preloadUint(256);
    var ds = contract.getData().beginParse();
    var elect = ds.loadDict();
    if ((srcWc + 1) != 0 || (srcAddr != configAddr) || elect == null) {
        return;
    }
    var election = unpackElect(elect);
    if ((election.electAt != queryId) | !election.finished) {
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
            ton("0"),
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
            ton("0"),
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
        body: (0xf96f7324, queryId),
    });

    reply.send(SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE);
}


fun afterCodeUpgrade(sAddr: address, cs: slice, queryId: int) {
    sendMessageBack(sAddr, 0xce436f64, queryId, 0x4e436f64, ton("0"), 64);
}

fun upgradeCode(sAddr: address, cs: slice, queryId: int): bool {
    val cAddr = blockchain.configParam(0);
    if (cAddr == null) {
        // no configuration smart contract known
        return false;
    }
    val configAddr = cAddr!.beginParse().preloadUint(256);
    val (srcWc, srcAddr) = sAddr.getWorkchainAndHash();
    if ((srcWc + 1) != 0 || (srcAddr != configAddr)) {
        // not from configuration smart contract, return error
        return false;
    }
    acceptExternalMessage();
    val code = cs.loadRef();
    contract.setCodePostponed(code);
    if (!cs.isEmpty()) {
        setTvmRegisterC3(transformSliceToContinuation(code.beginParse()));
        afterCodeUpgrade(sAddr, cs, queryId);
        throw (0);
    }
    return true;
}

fun registerComplaint(sAddr: address, complaint: slice, msgValue: coins): int {
    var (srcWc, srcAddr) = sAddr.getWorkchainAndHash();
    if ((srcWc + 1) != 0) {
        // not from masterchain, return error
        return -1;
    }
    if (complaint.depth() >= 128) {
        return -3; // invalid complaint
    }
    var data = loadContractData();
    var electionId = complaint.loadUint(32);
    var (fs, found) = data.pastElections.uDictGet(32, electionId);
    if (!found) {
        // election not found
        return -2;
    }
    fs = fs!;
    var expireIn = fs.preloadUint(32) - blockchain.now();
    if (expireIn <= 0) {
        // already expired
        return -4;
    }
    val vc = unpackComplaint(complaint);
    vc.rewardAddr = srcAddr;
    vc.createdAt = blockchain.now();
    // compute complaint storage/creation price
    val pricing = getComplaintPrices();
    val (_, bits, refs) = complaint.calculateSizeStrict(4096);
    val pps = (bits + 1024) * pricing.bitPrice + (refs + 2) * pricing.cellPrice;
    vc.paid = pps * expireIn + pricing.deposit;
    if (msgValue < vc.paid + ton("1")) {
        // not enough money
        return -5;
    }
    // re-pack modified complaint
    val newComplaint = packComplaint(vc).endCell();
    val pe = unpackPastElection(fs);
    val (validatorFsOpt, validatorFound) = pe.frozenDict.uDictGet(256, vc.validatorPubkey);
    if (!validatorFound) {
        // no such validator, cannot complain
        return -6;
    }
    val validatorFs = validatorFsOpt!;
    validatorFs.skipBits(256 + 64); // addr weight
    var validatorStake = validatorFs.loadCoins();
    var fine = vc.suggestedFine + muldiv_f(validatorStake, vc.suggestedFinePart, 1 << 32);
    if (fine > validatorStake) {
        // validator's stake is less than suggested fine
        return -7;
    }
    if (fine <= vc.paid) {
        // fine is less than the money paid for creating complaint
        return -8;
    }
    // create complaint status
    var cstatus = packComplaintStatus(ComplaintStatus {
        complaint: newComplaint,
        voters: createEmptyDict(),
        vsetId: 0,
        weightRemaining: 0,
    });
    // save complaint status into complaints
    var cplId = newComplaint.hash();
    if (!pe.complaints.uDictSetBuilderIfNotExists(256, cplId, cstatus)) {
        return -9; // complaint already exists
    }
    // pack past election info
    data.pastElections.uDictSetBuilder(32, electionId, packPastElection(pe));
    // pack persistent data
    storeContractData(data);
    return vc.paid;
}

struct PunishResult {
    credits: dict
    frozen: dict
    fineUnalloc: coins
    fine: coins
}

fun punish(credits: dict, frozen: dict, complaint: cell): PunishResult {
    val vc = unpackComplaint(complaint.beginParse());
    val (csOpt, found) = frozen.uDictGet(256, vc.validatorPubkey);
    if (!found) {
        // no validator to punish
        return PunishResult {
            credits,
            frozen,
            fineUnalloc: ton("0"),
            fine: ton("0"),
        };
    }
    val cs = csOpt!;
    val addr = cs.loadUint(256);
    val weight = cs.loadUint(64);
    var stake = cs.loadCoins();
    val banned = cs.loadInt(1);

    cs.assertEnd();

    var fine = min_f(stake, vc.suggestedFine + muldiv_f(stake, vc.suggestedFinePart, 1 << 32));
    stake -= fine;
    frozen = frozen.uDictSetBuilder(
        256,
        vc.validatorPubkey,
        beginCell().storeUint(addr, 256).storeUint(weight, 64).storeCoins(stake).storeInt(banned, 1)
    );
    val reward = min_f(fine >> 3, vc.paid * 8);
    val newCredits = creditTo(credits, vc.rewardAddr, reward);
    return PunishResult {
        credits: newCredits,
        frozen: frozen,
        fineUnalloc: fine - reward,
        fine: fine,
    };
}

fun registerVote(complaints: dict, chash: int, idx: int, weight: int): (dict, cell?, int) {
    val (cStatusOpt, found) = complaints.uDictGet(256, chash);
    if (!found) {
        // complaint not found
        return (complaints, null, -1);
    }
    val cStatus = cStatusOpt!;
    val currentVset = getCurrentVset();
    val curVsetId = currentVset.vset.hash();
    val cs = unpackComplaintStatus(cStatus);
    var vsetOld = (cs.vsetId != curVsetId);
    if ((cs.weightRemaining < 0) & vsetOld) {
        // previous validator set already collected 2/3 votes, skip new votes
        return (complaints, null, -3);
    }
    if (vsetOld) {
        // complaint votes belong to a previous validator set, reset voting
        cs.vsetId = curVsetId;
        cs.voters = createEmptyDict();
        cs.weightRemaining = muldiv_f(currentVset.totalWeight, 2, 3);
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
    complaints = complaints.uDictSetBuilder(256, chash, packComplaintStatus(cs));
    if (oldWr >= 0) {
        // not enough votes or already accepted
        return (complaints, null, 1);
    }
    // complaint wins, prepare punishment
    return (complaints, cs.complaint, 2);
}

fun proceedRegisterVote(electionId: int, chash: int, idx: int, weight: int): int {
    val data = loadContractData();
    val (fsOpt, found) = data.pastElections.uDictGet(32, electionId);
    if (!found) {
        // election not found
        return -2;
    }
    val fs = fsOpt!;
    var pe = unpackPastElection(fs);
    var (newComplaints, acceptedComplaint, status) = registerVote(pe.complaints, chash, idx, weight);
    if (status <= 0) {
        return status;
    }
    pe.complaints = newComplaints;
    if (acceptedComplaint != null) {
        val (newCredits, newFrozenDict, fineUnalloc, fineCollected) = punish(
            data.credits,
            pe.frozenDict,
            acceptedComplaint
        );
        data.credits = newCredits;
        pe.frozenDict = newFrozenDict;
        data.grams += fineUnalloc;
        pe.totalStake -= fineCollected;
    }
    data.pastElections.uDictSetBuilder(32, electionId, packPastElection(pe));
    storeContractData(data);
    return status;
}

// Tick-tock implementation
fun onRunTickTock(isTock: bool) {
    // check whether an election is being conducted
    var ds = contract.getData().beginParse();
    var (elect, credits) = (ds.loadDict(), ds.loadDict());
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
    if (updateActiveVsetId()) {
        return; // active validator set id updated, exit
    }
    checkUnfreeze();
}

fun postponeElections(): bool {
    return false;
}

// computes the total stake out of the first n entries of list l
fun computeTotalStake(l: tuple, n: int, mStake: coins): coins {
    var totStake = ton("0");
    var currentList = l;
    repeat (n) {
        var (head, newList) = listSplit<tuple>(currentList);
        currentList = newList;
        var stake = head.get<coins>(0);
        var maxF = head.get<int>(1);
        stake = min_f(stake, (maxF * mStake) >> 16);
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

    minValidators = max_f(minValidators, 1);
    var n = 0;
    var sdict = createEmptyDict();
    var pubkey = -1;
    do {
        var (nextKeyOpt, memberCsOpt, found) = members.uDictGetNext(256, pubkey);
        if (found) {
            pubkey = nextKeyOpt!;
            val memberCs = memberCsOpt!;

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
                beginCell().storeUint(min_f(maxFactor, maxStakeFactor), 32).storeUint(addr, 256)
                    .storeUint(adnlAddr, 256)
            );
            n += 1;
        }
    } while (found);
    n = min_f(n, maxValidators);
    if (n < minValidators) {
        return (credits, createEmptyDict(), 0, createEmptyDict(), ton("0"), 0);
    }
    var l = createEmptyList();

    do {
        var (keyOpt, validatorCsOpt, found) = sdict.sDictDeleteFirstAndGet(128 + 32 + 256);
        if (found) {
            val key = keyOpt!;
            val validatorCs = validatorCsOpt!;

            var stake = min_f(key.loadUint(128), maxStake);
            key.loadUint(32); // skip time
            var pubkey = key.preloadUint(256);

            var maxF = validatorCs.loadUint(32);
            validatorCs.loadUint(256); // skip addr
            var adnlAddr = validatorCs.preloadUint(256);
            l = listPrepend([stake, maxF, pubkey, adnlAddr], l);
        }
    } while (found);
    // l is the list of all stakes in decreasing order
    var i = minValidators - 1;
    var l1 = l;
    repeat (i) {
        l1 = listGetTail(l1);
    }

    var (bestStake, m) = (ton("0"), 0);
    do {
        val (head: tuple, newList) = listSplit(l1);
        l1 = newList;
        var stake = head.get<coins>(0);
        i += 1;
        if (stake >= minStake) {
            val totStake = computeTotalStake(l, i, stake);
            if (totStake > bestStake) {
                (bestStake, m) = (totStake, i);
            }
        }
    } while (i < n);

    if ((m == 0) | (bestStake < minTotalStake)) {
        return (credits, createEmptyDict(), 0, createEmptyDict(), ton("0"), 0);
    }
    // we have to select first m validators from list l
    l.stackMoveToTop();
    l1 = l;

    repeat (m - 1) {
        l1 = listGetTail(l1);
    }

    val head = listGetHead<tuple>(l1); //todo: not sure. need to test
    val mStake = head.get<coins>(0);

    // create both the new validator set and the refund set
    i = 0; //reset counter
    var totStake = ton("0");
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
        val value = valueOpt!;

        value.loadCoins(); // skip stake
        value.skipBits(64); // skip time and maxFactor
        val srcAddr = value.preloadUint(256);

        if (i < m) {
            // one of the first m members, include into validator set
            var trueStake = min_f(stake, (maxF * mStake) >> 16);
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
                beginCell().storeUint(srcAddr, 256).storeUint(weight, 64).storeCoins(trueStake)
                    .storeInt(false, 1)
            );
        }
        if (stake != ton("0")) {
            // non-zero unused part of the stake, credit to the source address
            credits = creditTo(credits, srcAddr, stake);
        }
        i += 1;
    } while (currentList != null);
    assert(totStake == bestStake, 49);
    return (credits, vset, totWeight, frozen, totStake, m);
}

fun conductElections(ds: slice, elect: cell, credits: dict): bool {
    var election = unpackElect(elect);
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
    elect = packElect(Election {
        electAt: election.electAt,
        electClose: election.electClose,
        minStake: minStake,
        totalStake: election.totalStake,
        members: election.members,
        failed: failed,
        finished: finished,
    });

    if (cnt == 0) {
        // elections failed, set elect_failed to true
        contract.setData(beginCell().storeDict(elect).storeDict(newCredits).storeSlice(ds).endCell());
        return postponeElections();
    }
    // serialize a query to the configuration smart contract
    // to install the computed validator set as the next validator set
    var validatorConf = getValidatorConf();
    var start = max_f(blockchain.now() + validatorConf.electionsEndBefore - 60, election.electAt);
    var mainValidators = blockchain.configParam(16)!.beginParse().skipBits(16).preloadUint(16);
    var vset = beginCell().storeUint(0x12, 8) // validators_ext#12
        .storeUint(start, 32) // utime_since:uint32
        .storeUint(start + validatorConf.electedFor, 32) // utime_until:uint32
        .storeUint(cnt, 16) // total:(## 16)
        .storeUint(min_f(cnt, mainValidators), 16) // main:(## 16)
        .storeUint(totalWeight, 64) // total_weight:uint64
        .storeDict(vdict) // list:(HashmapE 16 ValidatorDescr)
        .endCell();
    var configAddr = blockchain.configParam(0)!.beginParse().preloadUint(256);
    sendValidatorSetToConfig(configAddr, vset, election.electAt);
    // add frozen to the dictionary of past elections
    var pastElections = ds.loadDict();
    pastElections = pastElections.uDictSetBuilder(
        32,
        election.electAt,
        packPastElection(PastElection {
            unfreezeAt: start + validatorConf.electedFor + validatorConf.stakeHeldFor,
            stakeHeld: validatorConf.stakeHeldFor,
            vsetHash: vset.hash(),
            frozenDict: frozen,
            totalStake: totalStakes,
            bonuses: ton("0"),
            complaints: createEmptyDict(),
        })
    );
    // store credits and frozen until end
    contract.setData(beginCell().storeDict(elect).storeDict(newCredits).storeDict(pastElections)
        .storeSlice(ds)
        .endCell());
    return true;
}

fun updateActiveVsetId(): bool {
    val data = loadContractData();
    val curHash = blockchain.configParam(34)!.hash();
    if (curHash == data.activeHash) {
        // validator set unchanged
        return false;
    }
    if (data.activeId != 0) {
        // activeId becomes inactive
        var (fsOpt, found) = data.pastElections.uDictGet(32, data.activeId);
        if (found) {
            val fs = fsOpt!;

            // adjust unfreeze time of this validator set
            var unfreezeTime = fs.loadUint(32);
            val fs0 = fs;
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
            val fs = fsOpt!;
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
                data.activeId = id;
                // found
                found = false;
            }
        }
    } while (found);
    if (id == -1) {
        data.activeId = 0;
    }
    data.activeHash = curHash;
    storeContractData(data);
    return true;
}

fun cellHashEq(vset: cell?, expectedVsetHash: int): bool {
    return vset == null ? false : vset.hash() == expectedVsetHash;
}

fun validatorSetInstalled(ds: slice, elect: cell, credits: dict): bool {
    val election = unpackElect(elect);
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
    val fs = fsOpt!;
    // recover validator set hash
    val vsetHash = fs.skipBits(64).preloadUint(256);
    if (
        cellHashEq(blockchain.configParam(34), vsetHash) |
        cellHashEq(blockchain.configParam(36), vsetHash)
    ) {
        // this validator set has been installed, forget elections
        contract.setData(beginCell().storeInt(false, 1) // forget current elections
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
    val data = loadContractData();
    var id = -1;
    do {
        var (nextKeyOpt, fsOpt, found) = data.pastElections.uDictGetNext(32, id);
        if (found) {
            id = nextKeyOpt!;
            val fs = fsOpt!;
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
                storeContractData(data);
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
    if ((myWc + 1) | (myAddr != electorAddr)) {
        // this smart contract is not the elections smart contract anymore, no new elections
        return false;
    }
    var curVset = blockchain.configParam(34); // current validator set
    if (curVset == null) {
        return false;
    }
    curVset = curVset!;

    val validatorConf = getValidatorConf();
    val curValidUntil = curVset.beginParse().skipBits(8 + 32).preloadUint(32);
    var t = blockchain.now();
    val t0 = curValidUntil - validatorConf.electionsBeginBefore;
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
    val electAt = t + validatorConf.electionsBeginBefore;
    val electClose = electAt - validatorConf.electionsEndBefore;
    elect = packElect(Election {
        electAt: electAt,
        electClose: electClose,
        minStake: minStake,
        totalStake: ton("0"),
        members: createEmptyDict(),
        failed: false,
        finished: false,
    });
    contract.setData(beginCell().storeDict(elect).storeDict(credits).storeSlice(ds).endCell());
    return true;
}

// Main message handler
fun onInternalMessage(msgValue: coins, inMsgCell: cell, inMsgBody: slice) {
    val cs = inMsgCell.beginParse();
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
    if (op == 0x4e73744b) {
        // new stake message
        processNewStake(sAddr, msgValue, inMsgBody, queryId);
        return;
    }
    if (op == 0x47657424) {
        // recover stake request
        recoverStake(op, sAddr, inMsgBody, queryId);
        return;
    }
    if (op == 0x4e436f64) {
        // upgrade code (accepted only from configuration smart contract)
        val ok = upgradeCode(sAddr, inMsgBody, queryId);
        sendMessageBack(sAddr, ok ? 0xce436f64 : 0xffffffff, queryId, op, ton("0"), 64);
        return;
    }
    var cfgOk = (op == 0xee764f4b);
    if (cfgOk | (op == 0xee764f6f)) {
        // confirmation from configuration smart contract
        configSetConfirmed(sAddr, inMsgBody, queryId, cfgOk);
        return;
    }
    if (op == 0x52674370) {
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
        sendMessageBack(sAddr, ansTag + 0xf2676350, queryId, op, ton("0"), mode);
        return;
    }
    if (op == 0x56744370) {
        // vote for a complaint
        val signature = inMsgBody.loadBits(512);
        val msgBody = inMsgBody;
        val (signTag, idx, electId, chash) = (
            inMsgBody.loadUint(32),
            inMsgBody.loadUint(16),
            inMsgBody.loadUint(32),
            inMsgBody.loadUint(256)
        );
        inMsgBody.assertEnd();

        assert(signTag == 0x56744350, 37);
        val vdescr = getValidatorDescr(idx);
        assert(vdescr.value != null, 34);
        val valInfo = unpackValidatorDescr(vdescr.value);
        assert(isSliceSignatureValid(msgBody, signature, valInfo.pubkey), 34);
        val res = proceedRegisterVote(electId, chash, idx, valInfo.weight);
        sendMessageBack(
            sAddr,
            res + 0xd6745240,
            queryId,
            op,
            ton("0"),
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
            ton("0"),
            SEND_MODE_CARRY_ALL_REMAINING_MESSAGE_VALUE
        );
        return;
    }// unknown answer, ignore
}

// Helper functions
fun min_f(a: coins, b: coins): coins {
    return a < b ? a : b;
}

fun max_f(a: int, b: int): int {
    return a > b ? a : b;
}

fun muldiv_f(a: coins, b: int, c: int): coins {
    return (a * b) / c;
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
        return ton("0");
    }
    val election = unpackElect(elect!);
    val (mem, found) = election.members.uDictGet(256, validatorPubkey);
    return found ? mem!.loadCoins() : ton("0");
}

// returns the list of all participants of current elections with their stakes
get fun participantList(): tuple {
    val elect = contract.getData().beginParse().preloadDict();
    if (elect == null) {
        return ();
    }
    val election = unpackElect(elect!);
    var l = [];
    var id = (1 << 255) + ((1 << 255) - 1);
    do {
        var (nextKey, fs, f) = election.members.uDictGetPrev(256, id);
        if (f) {
            id = nextKey!;
            fs = fs!;
            l = ((id, fs.loadCoins()), l);
        }
    } while (f);
    return l;
}

// returns the list of all participants of current elections with their data
get fun participantListExtended(): (int, int, coins, coins, tuple, bool, bool) {
    var elect = contract.getData().beginParse().preloadDict();
    if (elect == null) {
        return (0, 0, ton("0"), ton("0"), (), false, false);
    }
    val election = unpackElect(elect);
    var l = [];
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

            l = listPrepend([id, [stake, maxFactor, addr, adnlAddr]], l);
        }
    } while (found);
    return (
        election.electAt,
        election.electClose,
        election.minStake,
        election.totalStake,
        l,
        election.failed,
        election.finished
    );
}

// computes the return stake
get fun computeReturnedStake(walletAddr: int): coins {
    val cs = contract.getData().beginParse();
    val (_, credits) = (cs.loadDict(), cs.loadDict());
    val (valueOpt, found) = credits.uDictGet(256, walletAddr);
    return found ? valueOpt!.loadCoins() : ton("0");
}

// returns the list of past election ids
get fun pastElectionIds(): tuple {
    val data = loadContractData();
    var id = (1 << 32);
    var list = [];
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
    val pricing = getComplaintPrices();
    val pps = (bits + 1024) * pricing.bitPrice + (refs + 2) * pricing.cellPrice;
    val paid = pps * expireIn + pricing.deposit;
    return paid + ton("1");
}
