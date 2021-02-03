import * as chai from "chai";
import chaiAsPromised from "chai-as-promised";
import { solidity } from "ethereum-waffle";

chai.use(solidity);
chai.use(chaiAsPromised);

export const expect = chai.expect;
