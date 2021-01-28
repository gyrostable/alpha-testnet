import * as path from "path";
import * as webpack from "webpack";

const config: webpack.Configuration = {
  mode: "production",
  entry: "./index.ts",
  devtool: "source-map",
  module: {
    rules: [
      {
        test: /\.tsx?$/,
        use: [{ loader: "ts-loader", options: { configFile: "tsconfig.webpack.json" } }],
        exclude: /node_modules/,
      },
    ],
  },
  resolve: {
    extensions: [".tsx", ".ts", ".js"],
  },
  output: {
    path: path.resolve(__dirname, "dist"),
    filename: "gyro-core.bundle.js",
    library: "gryo-core",
    libraryTarget: "commonjs",
    globalObject: "this",
  },
  externals: {
    ethers: "ethers",
    "@ethersproject/contracts": "@ethersproject/contracts",
  },
};

export default config;
