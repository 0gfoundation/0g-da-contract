import { task, types } from "hardhat/config";
import { UpgradeableBeacon } from "../../typechain-types";
import { BN254 } from "../../typechain-types/contracts/DAEntrance";
import { DARegistry } from "../../typechain-types/contracts/DARegistry";
import { BEACON_PROXY, CONTRACTS, Factories, getRawDeployment, UPGRADEABLE_BEACON } from "../utils/utils";

const REGISTRY_OWNER = "0x2d7f2d2286994477ba878f321b17a7e40e52cda4";
const REGISTRY_IMPLEMENTATION = "0x7ad29425f6d68ed6bd8eb8a77d73bb2ad81b8afa";
const REGISTRY_BEACON = "0x762662fb644cdd051f35e0dd8fb6ac15a4bf65ad";
const REGISTRY_PROXY = "0x20f30b2584f3096ea0d6c18c3b5cacc0585e12fc";

task("registry:raw", "get raw transaction")
    .addParam("key", "private key", undefined, types.string, false)
    .setAction(async (taskArgs: { key: string; owner: string }, hre) => {
        // implementation
        console.log(
            `implementation raw tx: ${await getRawDeployment(hre, CONTRACTS.DARegistry.name, taskArgs.key, [], 0)}`
        );
        // beacon
        console.log(
            `beacon raw tx: ${await getRawDeployment(
                hre,
                UPGRADEABLE_BEACON,
                taskArgs.key,
                [REGISTRY_IMPLEMENTATION, REGISTRY_OWNER],
                1
            )}`
        );
        // proxy
        console.log(
            `proxy raw tx: ${await getRawDeployment(hre, BEACON_PROXY, taskArgs.key, [REGISTRY_BEACON, "0x"], 2)}`
        );
    });

task("registry:initialize", "check wa0gi agency status").setAction(async (_taskArgs, hre) => {
    const signer = await hre.ethers.getSigner((await hre.getNamedAccounts()).deployer);
    const registry: DARegistry = await hre.ethers.getContractAt("DARegistry", REGISTRY_PROXY, signer);
    await (await registry.initialize()).wait();
});

task("registry:check", "check wa0gi agency status").setAction(async (_taskArgs, hre) => {
    const beacon: UpgradeableBeacon = await hre.ethers.getContractAt(UPGRADEABLE_BEACON, REGISTRY_BEACON);
    console.log(`beacon owner: ${await beacon.owner()}`);
    console.log(`beacon implementation: ${await beacon.implementation()} / ${REGISTRY_IMPLEMENTATION}`);
    const registry: DARegistry = await hre.ethers.getContractAt("DARegistry", REGISTRY_PROXY);
    console.log(`registry owner: ${await registry.owner()}`);
    console.log(`da signers: ${await registry.DA_SIGNERS()}`);
});

task("dasigners:getcode", "send").setAction(async (_, hre) => {
    console.log(await hre.ethers.provider.getCode("0x1cd0690ff9a693f5ef2dd976660a8dafc81a109c"));
});

task("dasigners:params", "call precompile contract").setAction(async (_, hre) => {
    const precompile = Factories.IDASigners__factory.connect(
        "0x0000000000000000000000000000000000001000",
        (await hre.ethers.getSigners())[0]
    );
    console.log(await precompile.params());
});

task("dasigners:epoch", "call precompile contract").setAction(async (_, hre) => {
    const precompile = Factories.IDASigners__factory.connect(
        "0x0000000000000000000000000000000000001000",
        (await hre.ethers.getSigners())[0]
    );
    console.log(await precompile.epochNumber());
    console.log((await hre.ethers.provider.getNetwork()).chainId);
    const { getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    console.log(await hre.ethers.provider.getBalance(deployer));
});

task("dasigners:makeepoch", "call precompile contract").setAction(async (_, hre) => {
    const precompile = Factories.IDASigners__factory.connect(
        "0x0000000000000000000000000000000000001000",
        (await hre.ethers.getSigners())[0]
    );
    console.log(await precompile.makeEpoch());
});

task("dasigners:quorum", "call precompile contract")
    .addParam("epoch", "epoch number", undefined, types.int, false)
    .setAction(async (args: { epoch: number }, hre) => {
        const precompile = Factories.IDASigners__factory.connect(
            "0x0000000000000000000000000000000000001000",
            (await hre.ethers.getSigners())[0]
        );
        console.log(await precompile.quorumCount(args.epoch));
    });

task("dasigners:updatesocket", "update socket").setAction(async (_, hre) => {
    const precompile = Factories.IDASigners__factory.connect(
        "0x0000000000000000000000000000000000001000",
        (await hre.ethers.getSigners())[0]
    );
    const receipt = await (await precompile.updateSocket("0.0.0.0:2345")).wait();
    console.log(receipt);
    if (receipt) {
        console.log(receipt.logs);
    }
});

task("dasigners:getsigner", "get signer")
    .addParam("addr", "signer addr", undefined, types.string, false)
    .setAction(async (args: { addr: string }, hre) => {
        const precompile = Factories.IDASigners__factory.connect(
            "0x0000000000000000000000000000000000001000",
            (await hre.ethers.getSigners())[0]
        );
        await precompile.updateSocket.staticCall("12345");
        const addrs = args.addr.split(",");
        const signers = await precompile.getSigner(addrs);
        console.log(signers);
    });

task("dasigners:issigner", "is signer").setAction(async (_, hre) => {
    const precompile = Factories.IDASigners__factory.connect(
        "0x0000000000000000000000000000000000001000",
        (await hre.ethers.getSigners())[0]
    );
    const { getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    console.log(await precompile.isSigner(deployer));
});

task("dasigners:registered", "is registered for next epoch").setAction(async (_, hre) => {
    const precompile = Factories.IDASigners__factory.connect(
        "0x0000000000000000000000000000000000001000",
        (await hre.ethers.getSigners())[0]
    );
    const { getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    const nextEpoch = (await precompile.epochNumber()) + 1n;
    console.log(await precompile.registeredEpoch(deployer, nextEpoch));
});

task("dasigners:getquorum", "get quorum")
    .addParam("epoch", "epoch number", undefined, types.int, false)
    .addParam("quorum", "quorum id", undefined, types.int, false)
    .setAction(async (args: { epoch: number; quorum: number }, hre) => {
        const precompile = Factories.IDASigners__factory.connect(
            "0x0000000000000000000000000000000000001000",
            (await hre.ethers.getSigners())[0]
        );
        const quorum = await precompile.getQuorum(args.epoch, args.quorum);
        console.log(quorum);
    });

task("dasigners:getallquorum", "get quorum")
    .addParam("epoch", "epoch number", undefined, types.int, false)
    .setAction(async (args: { epoch: number }, hre) => {
        const precompile = Factories.IDASigners__factory.connect(
            "0x0000000000000000000000000000000000001000",
            (await hre.ethers.getSigners())[0]
        );
        const cnt = await precompile.quorumCount(args.epoch);
        const res: { [key: number]: { [key: string]: number } } = {};
        for (let i = 0; i < cnt; ++i) {
            const quorum = await precompile.getQuorum(args.epoch, i);
            res[i] = {};
            for (const j of quorum) {
                if (!(j in res[i])) {
                    res[i][j] = 0;
                }
                ++res[i][j];
            }
        }
        console.log(res);
    });

task("dasigners:getallsigners", "get all signers in quorums of latest epoch").setAction(async (_taskArgs, hre) => {
    const precompile = Factories.IDASigners__factory.connect(
        "0x0000000000000000000000000000000000001000",
        (await hre.ethers.getSigners())[0]
    );
    const epoch = await precompile.epochNumber();
    const cnt = await precompile.quorumCount(epoch);
    const res: { [key: string]: unknown } = {};
    for (let i = 0; i < cnt; ++i) {
        const quorum = await precompile.getQuorum(epoch, i);
        for (const j of quorum) {
            if (!(j in res)) {
                const signer = await precompile.getSigner([j]);
                console.log(`${j}: ${signer[0].socket}`);
                res[j] = signer[0].socket;
            }
        }
    }
    console.log(res);
});

task("dasigners:getquorumrow", "get quorum row")
    .addParam("epoch", "epoch number", undefined, types.int, false)
    .addParam("quorum", "quorum id", undefined, types.int, false)
    .addParam("row", "row index", undefined, types.int, false)
    .setAction(async (args: { epoch: number; quorum: number; row: number }, hre) => {
        const precompile = Factories.IDASigners__factory.connect(
            "0x0000000000000000000000000000000000001000",
            (await hre.ethers.getSigners())[0]
        );
        console.log(await precompile.getQuorumRow(args.epoch, args.quorum, args.row));
    });

task("dasigners:getaggpkg1", "get aggregate public key g1")
    .addParam("epoch", "epoch number", undefined, types.int, false)
    .addParam("quorum", "quorum id", undefined, types.int, false)
    .setAction(async (args: { epoch: number; quorum: number }, hre) => {
        const precompile = Factories.IDASigners__factory.connect(
            "0x0000000000000000000000000000000000001000",
            (await hre.ethers.getSigners())[0]
        );
        console.log(
            await precompile.getAggPkG1(
                args.epoch,
                args.quorum,
                "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
            )
        );
    });

task("dasigners:register", "register signer").setAction(async (_, hre) => {
    const signer = await hre.ethers.getSigner((await hre.getNamedAccounts()).deployer);
    const registry: DARegistry = await hre.ethers.getContractAt("DARegistry", REGISTRY_PROXY, signer);
    const { getNamedAccounts } = hre;
    const { deployer } = await getNamedAccounts();
    console.log(await signer.getAddress(), deployer);
    const receipt = await (
        await registry.registerSigner(
            {
                signer: deployer,
                socket: "0.0.0.0:1234",
                pkG1: {
                    X: 1n,
                    Y: 2n,
                },
                pkG2: {
                    X: [
                        10857046999023057135944570762232829481370756359578518086990519993285655852781n,
                        11559732032986387107991004021392285783925812861821192530917403151452391805634n,
                    ],
                    Y: [
                        8495653923123431417604973247489272438418190587263600148770280649306958101930n,
                        4082367875863433681332203403145435568316851327593401208105741076214120093531n,
                    ],
                },
            },
            {
                X: 2781655066679735511160523731957481670837110573795623296346013601350295834752n,
                Y: 1195165268465843865669265814445603798831024764885296826356565268422748505n,
            }
        )
    ).wait();
    console.log(receipt);
    if (receipt) {
        console.log(receipt.logs);
    }
});

task("dasigners:registerepoch", "register epoch").setAction(async (_, hre) => {
    const precompile = Factories.IDASigners__factory.connect(
        "0x0000000000000000000000000000000000001000",
        (await hre.ethers.getSigners())[0]
    );
    const signer = await hre.ethers.getSigner((await hre.getNamedAccounts()).deployer);
    const registry: DARegistry = await hre.ethers.getContractAt("DARegistry", REGISTRY_PROXY, signer);
    const nextEpoch = (await precompile.epochNumber()) + 1n;
    if (nextEpoch >= registerEpochSignatures.length) {
        throw new Error("no signature");
    }
    const signature: BN254.G1PointStruct = registerEpochSignatures[Number(nextEpoch)];
    const receipt = await (await registry.registerNextEpoch(signature)).wait();
    console.log(receipt);
    if (receipt) {
        console.log(receipt.logs);
    }
});

const registerEpochSignatures: BN254.G1PointStruct[] = [
    {
        X: 3501799824264872025715921524193049610542832482790883817344537711787766968070n,
        Y: 1432588270851505983781156393469732491965271284748111822841717250737922837689n,
    },
    {
        X: 2654047180780348826230479599343832137447131635813041780776393035198481413129n,
        Y: 9531307382533940073066420834203882004730012076487386472493992560446295511696n,
    },
    {
        X: 4304278622045626684521584478713646779210437440603295237297306297798535875951n,
        Y: 16682634955812291870242450671033321197588321121491925805024066849211780420653n,
    },
    {
        X: 12399603264892763375236758379636093859401567514822221052280561433019663472038n,
        Y: 70804003904885149932412044993411276979767441525105105443873200346019976664n,
    },
    {
        X: 5316237743813539062986944721611337709057203743072783001532315703232583327635n,
        Y: 6619688105594905766145947172838568080960235529430159824854484509174120853141n,
    },
    {
        X: 5835304960297402352088614450366381805227540333245490490580284659444556994547n,
        Y: 1958785727643031506885883513901356753214592721682450161237543227710405584964n,
    },
    {
        X: 17265814897286081070697578025610165193239477080281565469160815917123105596099n,
        Y: 4574638219903877705331717731011761220937856399086958808457375027743369709943n,
    },
    {
        X: 11897720969687824279767372473921272168440754509208709303147194646994150156646n,
        Y: 18738204144033997008073646860438125807947220575193961524706350237599397420461n,
    },
    {
        X: 14425611987635442866118353238823252387309414820826470419793532594845886967883n,
        Y: 7878037285534371811060998971674866839456075880387975859026350690619744620995n,
    },
    {
        X: 14634318551875137904962131102306167786661775617270415211322207244357125596506n,
        Y: 7595668411355274440837172769684599792224908325423213473977987622142226797441n,
    },
    {
        X: 19520077828482194077047067898515731046401711927732937613754564124724526117320n,
        Y: 10628188007023691777435963912695592548946170242118547192479530144377344561242n,
    },
    {
        X: 6978121637441403885327434174875984154147298511278184348872684215074378709431n,
        Y: 19360022356333060346207872367420051507508547517427896070293099123384123522656n,
    },
    {
        X: 446958481009864158509608933570963971501203198765818073011867288905404438651n,
        Y: 4574763234136301923695607666601869797126103986262395511841801544108053764250n,
    },
    {
        X: 15978641984389885349872833603586121586793112122450514077355716540535592901531n,
        Y: 12431389951752295900776482756885797293895196832735909761883982651964088245378n,
    },
    {
        X: 95244290029134961119493552642784197083661600788552067493996328123673586992n,
        Y: 15926833679305521708062254036668421563181374988118168750396077924557183681842n,
    },
    {
        X: 2290202598476371200607605878172658785253233772051464170371657714038633699876n,
        Y: 18521621984700774745252589399240393163213471293611094814318928812918865045837n,
    },
    {
        X: 20769045305657357139020718454077389467426753072188123021261758870824986623662n,
        Y: 8649548780175612464102781765537169989051218336903760648905466364949505938438n,
    },
    {
        X: 6746242218278342031839866870461790259793447184943920223112699871256400881324n,
        Y: 6606773001557248016778238472123423370768357852825562847356268297202394238898n,
    },
    {
        X: 7803723152960168257590774534555274771369847277709592332554951659316267206274n,
        Y: 5110628379729852339572483896443163261727099211906888477485974559542578252032n,
    },
    {
        X: 4903799455252873438402197724866510537138845418366658545121814626957090344852n,
        Y: 19652921745980243123179223041559819406444739558102506513697558240888272075543n,
    },
    {
        X: 13512820250244813789907446712855910690001761791050912787968407190633712152387n,
        Y: 15931083214673956175647601405622196035288627274910160409678197265269742104579n,
    },
    {
        X: 1597699794637934387385636969627774166491494367746493581648862331792557433557n,
        Y: 15392559857136971189443534508764052986542649864862053269636083617775598753870n,
    },
    {
        X: 16193874669569145392482764977427744605166491496023189311947857702199629649067n,
        Y: 1556129286148039963165931467089423860603875780919184327918315260383685718815n,
    },
    {
        X: 21559758004622532391251624558242379029055978371579231226302025078970591307968n,
        Y: 15550663038625968465473042622601196759471376644593502562479266146464603628287n,
    },
    {
        X: 939909898245420039153212214737152174294522343366172568196924611165855656311n,
        Y: 15119831103244948814183352321474429910537162124251596131785179300055418598153n,
    },
    {
        X: 6223793892260521249805603844411875130150243881295989486155184089869593072197n,
        Y: 12000155423186878136457375412985375601070895892135862383109211744325802279283n,
    },
    {
        X: 11923875889719684634547143396376884327753753587265432440432626220878174312491n,
        Y: 1957406392862624411188024473716382820412577115443272949427734273139315725168n,
    },
    {
        X: 9142333076312467017627895234909599003834239025305256626572946197903180973701n,
        Y: 54494333579477863903000850388754235247657027453921734897572725513177918250n,
    },
    {
        X: 18561308990523027245961254075304662418421900002077575032913852407117216403451n,
        Y: 18640790309006372693318702259597867581620727803123750996872649663659819199892n,
    },
    {
        X: 18105296550250758973719003934399969132740858484071591145795133826641716063308n,
        Y: 8799826009441049068042578986117200581127576776578788558670067789384895987662n,
    },
    {
        X: 15057157459308896148119972245865191273288931606016308950663778217020166541475n,
        Y: 5760293662286901268965329981800691038601230596291744765827706775818031830961n,
    },
    {
        X: 19663095504607320432600480005663930335923393400029615188309844314860365852866n,
        Y: 11260334288321157680718090962940841015970844692908513230115584222497720890128n,
    },
    {
        X: 17902855977556847475094968928699009168102410688886009137634190889311864977521n,
        Y: 6835578781076802399112744128056681266385379143330705295260508502107015321444n,
    },
    {
        X: 11601126747860633521045054790759481159453066394279003015246876714363061985117n,
        Y: 3231840429959199815773233030625803159618987709995585769345363797124806331047n,
    },
    {
        X: 19119224814844754728960879900665968631370632685367741957032445015424167274089n,
        Y: 17550798526633874646339358810797999578677427722891371834096421881695323515311n,
    },
    {
        X: 10595614186600065091171539653528561972648712602850102980765168765511175693003n,
        Y: 5107426444805766515062964711296794132490445946736718950004947351604180318228n,
    },
    {
        X: 5743902701109070432153341474468177345442687498129607496100559385018894805318n,
        Y: 7852455137918825293004075226325775412490860396405128994847040083356533348872n,
    },
    {
        X: 17545466127273041296533314129370867399008881581394594187730774636773501349759n,
        Y: 4388854137923586929204796353135389508609996870521784213386452735536866570810n,
    },
    {
        X: 649079030169987328627706820718291217644549918144242527755167809066626443079n,
        Y: 4689896555208401266262678320668822137980581920336298206382280274788389834448n,
    },
    {
        X: 44427411629358958967481323893345478788576701239726422089088952981491209889n,
        Y: 13502804102711498553506628020209837470650641596079709408176996347380796842686n,
    },
    {
        X: 14407311994246053476762614162547746654583500803896395329094491666685303982237n,
        Y: 18185580211410290072546211094998622085949252919295740897702512757116574972897n,
    },
    {
        X: 10200441341562767454903156114864947885871982754784390804873854821459236600961n,
        Y: 17976402038188616762249034555373559390643704408754725440648520820225334857642n,
    },
    {
        X: 20676559188958933920894612448030955519271679641123933188692268263489289552816n,
        Y: 21834333458502940465400424983576014186101622158527958686574196373310804941059n,
    },
    {
        X: 3663421718631258076587828582898513176095927934227572811022102720828420571216n,
        Y: 632551236446809195088625391088989295865566665910676796468635612306799460967n,
    },
    {
        X: 21833583547380694571314948142862053239082699502478647305616682853789653672452n,
        Y: 2743927112576010678945403130681161628826315961207162244801070273387661210778n,
    },
    {
        X: 20884695854862036399890367779247406311957225799893745255195797992762155253437n,
        Y: 2236403520077879729600534285057725009635666782525432176031212463015188182829n,
    },
    {
        X: 6357099406127164203802605238141152784866513766300389679846030814396046658427n,
        Y: 8874021215612071770489959446197922431497407283876503680762041554749510390358n,
    },
    {
        X: 7850945959602123563734204248533260141858703901154675897692990261026348514602n,
        Y: 14804706030726353271124959006208349628794384480380519004404464279049207514539n,
    },
    {
        X: 11254513436488294327207924495794638510108581465638227044717421743995531148104n,
        Y: 17982425876080892155398785755885720377204256651295570377645244260777623843484n,
    },
    {
        X: 4580105763204103638939608424951954717177715621859988897689804375251140407530n,
        Y: 18435713776720114510559837544069469084019477349759679343731009193106276052750n,
    },
];
