# 这是官方要求提交的文件的结构，但是我们暂时不遵循

```
<project_name>/
├── README.md                  # 项目简介 + 复现步骤
├── src/                       # 设计源码（RTL / HLS / PS 侧软件）
├── sim/                       # 仿真或验证脚本与结果
├── build/                     # 可复现的构建脚本 + 综合与实现报告
├── board/                     # 上板工程、运行脚本与实测输出
── data/                      # 测试数据与参考结果
├── skill/                     # 技能包
│   └── README.md
└── report/                    # 设计报告 + 大模型协作记录
```

# 文件夹是这样的：

1. fpga_space_invaders是Vivado工程的文件夹，有gitignore，src/将来提交的时候从那里拿取
   - 双击fpga_space_invaders\fpga_space_invaders\fpga_space_invaders.xpr即可打开工程，gitignore的文件此时会重新自动生成
2. “说明”的gitignore比较简略（就是毙掉pycache），所以不要乱放东西，以下东西的草稿可以放在“说明”
   - 项目简介 + 复现步骤
   - 仿真或验证脚本与结果
   - 可复现的构建脚本 + 综合与实现报告
   - 技能包
   - 设计报告 + 大模型协作记录
3. 上板工程、运行脚本与实测输出，测试数据与参考结果先不搞单独的文件夹，最后再说
4. 那个Python程序也在说明里（scripts是完整游戏，script2是一个更简单的原型）
