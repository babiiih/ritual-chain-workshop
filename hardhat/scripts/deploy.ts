import hre from "hardhat";

async function main() {
  const [deployer] = await hre.viem.getWalletClients();
  console.log("Deploying with:", deployer.account.address);

  const contract = await hre.viem.deployContract("CommitRevealAIJudge", [], {
    value: 0n,
  });

  console.log("Deployed to:", contract.address);
  console.log("TX Hash:", contract.deployment?.transactionHash || "N/A");
}

main().catch(console.error);
