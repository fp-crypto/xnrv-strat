import pytest
from brownie import config
from brownie import Contract


@pytest.fixture
def gov(accounts):
    yield accounts.at("0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52", force=True)


@pytest.fixture
def whale(accounts):
    yield accounts.at("0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c", force=True)


@pytest.fixture
def user(accounts):
    yield accounts[0]


@pytest.fixture
def rewards(accounts):
    yield accounts[1]


@pytest.fixture
def guardian(accounts):
    yield accounts[2]


@pytest.fixture
def management(accounts):
    yield accounts[3]


@pytest.fixture
def strategist(accounts):
    yield accounts[4]


@pytest.fixture
def keeper(accounts):
    yield accounts[5]


@pytest.fixture
def token():
    token_address = "0x42F6f551ae042cBe50C739158b4f0CAC0Edb9096"
    yield Contract(token_address)


@pytest.fixture
def amount(accounts, token, user):
    amount = 10_000 * 10 ** token.decimals()
    # In order to get some funds for the token you are about to use,
    # it impersonate an exchange address to use it's funds.
    reserve = accounts.at("0x401479091d0F7b8AE437Ee8B054575cd33ea72Bd", force=True)
    token.transfer(user, amount, {"from": reserve})
    yield amount


@pytest.fixture
def vault(pm, gov, rewards, guardian, management, token):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(token, gov, rewards, "", "", guardian)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    vault.setManagementFee(0, {"from": gov})
    yield vault


@pytest.fixture
def strategy(strategist, keeper, vault, Strategy, gov):
    strategy = strategist.deploy(Strategy, vault)
    strategy.setKeeper(keeper)
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    yield strategy


@pytest.fixture
def weth():
    token_address = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"
    yield Contract(token_address)


@pytest.fixture
def weth_amout(gov, weth, whale):
    amout = 10 ** weth.decimals()
    weth.transfer(gov, amout, {"from": whale})
    yield amout


@pytest.fixture
def nrv_whale(accounts):
    yield accounts.at("0x319f1843a9d5e6532f7f18a9d90b2e9eaf5730ea", True)


@pytest.fixture(scope="session")
def RELATIVE_APPROX():
    yield 1e-5
