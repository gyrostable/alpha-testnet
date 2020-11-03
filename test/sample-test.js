const { expect } = require("chai");

describe("GyroCore", function () {
  let Greeter;
  let greeter;

  beforeEach(async () => {
    Greeter = await ethers.getContractFactory("GyroCore");
    greeter = await Greeter.deploy("Hello, world!");
  });

  it("Should return the new greeting once it's changed", async function () {
    await greeter.deployed();
    expect(await greeter.greet()).to.equal("Hello, world!");
  });
});
