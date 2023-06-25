# net-liquidity.ps1

PowerShell script to calculate [Net Liquidity](https://gist.github.com/dharmatech/c2dc1154167f3d1aed003aba7628a41e).

    Net Liquidity = Federal Reserve Balance sheet - Treasury General Account - Reverse Repo

# Screenshots

## Change Table

When you run this script, the change table will appear on the console:

![image](https://user-images.githubusercontent.com/20816/201480445-07a53489-58ff-4b27-ac56-f8a057084e6f.png)

The `SPX FV` column is the SPX Fair Value.

Green indicates an increase in Net Liquidity.

Red indicates a decrease in Net Liquidity.

## Net Liquidity chart

A chart for Net Liquidity will open in a browser:

![image](https://user-images.githubusercontent.com/20816/201480455-9e653277-ef0f-46e7-876d-34b22a1151e2.png)

## SPX Fair Value chart

A chart for SPX, SPX fair value, and the SPX fair value bands will open in a browser:

![image](https://user-images.githubusercontent.com/20816/201480461-be9742d7-548f-44af-bdba-5c8aae35341c.png)

# Platforms

The script has been tested on Windows and Ubuntu.

Let me know if you test it on macOS.

# When to run the script

- WALCL is updated Thursday at 4:30 PM Eastern.
- Reverse Repo is updated daily at 1:15 PM Eastern.
- TGA is updated daily at 4:00 PM Eastern. Value is for the previous day.

So it's usually best to run the script once a day after 4:00 PM Eastern.

TGA is reported for the previous day. So in general, only the previous day's Net Liquidity will be fully known. The script will still display the current day's preliminary Net Liquidity value which will include RRP and WALCL if updates for them are available.

# Downloading the script

Go to this page:

https://github.com/dharmatech/net-liquidity.ps1/blob/master/net-liquidity-walcl.ps1

Right-click **Raw** and select **Save link as...**:

![image](https://user-images.githubusercontent.com/20816/207929209-0edf4c12-1ece-44af-8640-0acf4621e452.png)

If you're on Windows, you may have to unblock the file from a PowerShell console:

    Unblock-File .\net-liquidity-walcl.ps1

Run the file at a PowerShell prompt:

    .\net-liquidity-walcl.ps1
