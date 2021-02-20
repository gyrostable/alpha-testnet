import * as path from "path";
import * as webpack from "webpack";
import CopyPlugin from "copy-webpack-plugin";

const config: webpack.Configuration = {
  mode: "production",
  entry: "./index.ts",
  devtool: "source-map",
  module: {
    rules: [
      {
        test: /(?<!\.d)\.tsx?$/,
        use: [{ loader: "ts-loader", options: { configFile: "tsconfig.webpack.json" } }],
        exclude: /node_modules/,
      },
      {
        test: /\.d\.ts$/,
        loader: "ignore-loader",
      },
    ],
  },
  resolve: {
    extensions: [".tsx", ".ts", ".js", ".d.ts"],
  },
  output: {
    path: path.resolve(__dirname, "dist"),
    filename: "gyro-core.bundle.js",
    libraryTarget: "commonjs",
    globalObject: "this",
  },
  externals: {
    ethers: "ethers",
    "@ethersproject/contracts": "@ethersproject/contracts",
  },
  plugins: [
    new CopyPlugin({
      patterns: [
        {
          from: "typechain/*.d.ts",
          to: "typechain/[name].[ext]",
        },
      ],
    }),
  ],
};

export default config;
