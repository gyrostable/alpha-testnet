import fs from "fs/promises";
import g from "glob";
import path from "path";
import { promisify } from "util";

export const glob = promisify(g);

const deploymentsPath = path.join(path.dirname(__dirname), "deployments");

async function main() {
  const deployments = await glob(path.join(deploymentsPath, "*/*.json"));
  const networks: Record<string, Record<string, string>> = {};
  for (const filepath of deployments) {
    const content = JSON.parse(await fs.readFile(filepath, "utf-8"));
    const filename = path.basename(filepath, ".json");
    const network = path.basename(path.dirname(filepath));
    if (!networks[network]) {
      networks[network] = {};
    }
    networks[network][filename] = content.address;
  }
  const result = { networks };
  const outputFile = path.join(path.dirname(__dirname), "deployments", "metadata.json");
  await fs.writeFile(outputFile, JSON.stringify(result), "utf-8");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
