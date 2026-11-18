# 雨线营地

Cooper Game 是一款 Godot 第一人称林地合作生存样片。1–4 人可以在同一网络收集材料、修屋避雨，或到鹿鸣湖看落日和银河。

## 试玩

房主需要 Node.js 24 和 Godot 4.7.2。可以从 [Actions](https://github.com/skysf/cooper-game/actions/workflows/coop.yml) 下载 Web 构建并解压到 `dist/coop/`，或安装 Python 3、NumPy 和 Pillow 后运行 `npm run coop:build:web` 生成。

在项目根目录运行 `npm run coop:lan`，然后打开[本机营地](http://localhost:4184/coop/?room=pine)。朋友使用终端打印的同网地址加入。

[试玩、构建与 CI](docs/play.md) · [合作实测](docs/coop.md) · [项目索引](AGENTS.md) · [MIT](LICENSE) · [素材许可与署名](THIRD_PARTY_NOTICES.md)
