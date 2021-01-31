import { BigNumber, BigNumberish } from "ethers";
import { ethers } from "hardhat";
import { MathTest, MathTest__factory } from "../typechain";
import BigDecimal from "bignumber.js";
import { expect } from "./chai";

describe("MathTest", () => {
  let mathTest: MathTest;

  beforeEach(async () => {
    const accounts = await ethers.getSigners();
    const wallet = accounts[0];
    mathTest = await new MathTest__factory(wallet).deploy();
  });

  function scale(value: BigNumberish, decimal: BigNumberish): BigNumber {
    return BigNumber.from(value).mul(BigNumber.from(10).pow(decimal));
  }

  describe("mulPow", () => {
    it("should exponentiate and multiply", async () => {
      for (let decimal = 2; decimal <= 18; decimal++) {
        const value = scale(180, decimal); // 180
        const base = scale(85, decimal - 1); // 8.5
        const exponent = scale(6, decimal - 1); // 0.6

        // 180 * 8.5 ^ 0.6 = 650.0157211540044

        //  value * (base ^ exponent)
        const expected = BigNumber.from(
          new BigDecimal(180)
            .multipliedBy(Math.pow(8.5, 0.6))
            .multipliedBy(Math.pow(10, 18))
            .toString()
        ).div(BigNumber.from(10).pow(18 - decimal));

        const result = await mathTest.mulPow(value, base, exponent, decimal);
        // console.log(
        //   "decimal",
        //   decimal,
        //   "result",
        //   result.toString(),
        //   "expected",
        //   expected.toString()
        // );
        expect(result.sub(expected).abs().lt(scale(1, 5))).to.be.true;
      }
    });
  });
});
