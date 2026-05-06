const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("========================================");
  console.log("  GIWA Sepolia Deployment");
  console.log("========================================");
  console.log("Deployer:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Balance:", ethers.formatEther(balance), "ETH\n");

  // ── 1. K-USDC 배포 ──────────────────────────────────────
  console.log("1) Deploying KUSDC (K-USDC Stablecoin)...");
  const KUSDC = await ethers.getContractFactory("KUSDC");
  const kusdc = await KUSDC.deploy(
    deployer.address, // owner (Franchise)
    deployer.address, // pauser
    deployer.address  // rescuer
  );
  await kusdc.waitForDeployment();
  const kusdcAddress = await kusdc.getAddress();
  console.log("   ✅ KUSDC deployed at:", kusdcAddress);

  // ── 2. CafePayment 배포 ──────────────────────────────────
  console.log("\n2) Deploying CafePayment...");
  const CafePayment = await ethers.getContractFactory("CafePayment");
  const cafe = await CafePayment.deploy(
    deployer.address, // owner (Franchise)
    deployer.address, // merchant (Cafe Owner)
    250               // feeRate: 2.5% (250 basis points)
  );
  await cafe.waitForDeployment();
  const cafeAddress = await cafe.getAddress();
  console.log("   ✅ CafePayment deployed at:", cafeAddress);

  // ── 3. 초기 설정 ─────────────────────────────────────────
  console.log("\n3) Initial setup...");

  // KUSDC를 CafePayment 화이트리스트에 추가
  const tx1 = await cafe.addWhitelistedToken(kusdcAddress);
  await tx1.wait();
  console.log("   ✅ KUSDC whitelisted in CafePayment");

  // deployer를 KUSDC Minter로 등록 (1,000,000 KUSDC 한도)
  const mintAllowance = ethers.parseUnits("1000000", 6); // 1M KUSDC
  const tx2 = await kusdc.configureMinter(deployer.address, mintAllowance);
  await tx2.wait();
  console.log("   ✅ Deployer configured as minter (1,000,000 KUSDC)");

  // ── 4. 테스트 민팅 ───────────────────────────────────────
  console.log("\n4) Minting test tokens...");
  const mintAmount = ethers.parseUnits("10000", 6); // 10,000 KUSDC
  const tx3 = await kusdc.mint(deployer.address, mintAmount);
  await tx3.wait();
  console.log("   ✅ Minted 10,000 KUSDC to deployer");

  const deployerBalance = await kusdc.balanceOf(deployer.address);
  console.log("   Deployer KUSDC balance:", ethers.formatUnits(deployerBalance, 6), "KUSDC");

  // ── 5. 결과 요약 ─────────────────────────────────────────
  console.log("\n========================================");
  console.log("  Deployment Complete!");
  console.log("========================================");
  console.log("KUSDC Address    :", kusdcAddress);
  console.log("CafePayment Addr :", cafeAddress);
  console.log("Network          : GIWA Sepolia (chainId: 91342)");
  console.log("Fee Rate         : 2.5%");
  console.log("Explorer         : https://explorer.giwa.io");
  console.log("\n[.env에 추가할 값]");
  console.log(`KUSDC_ADDRESS=${kusdcAddress}`);
  console.log(`CAFE_PAYMENT_ADDRESS=${cafeAddress}`);

  return { kusdcAddress, cafeAddress };
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
