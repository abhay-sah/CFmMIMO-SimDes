# CFmMIMO-SimDes
This describes the functionality of cell-free massive MIMO simulator created at 6G-Vigyan Lab, IIT Roorkee in collaboration with MathWorks, India.

**Note: The codebase is in Collaboration with MathWorks, and will work with MATLAB 2024b.**

## Code Setup

### 1. **Clone the GitHub Repository**

1. Open MATLAB 2024b.
2. Open the Command Window.
3. Use the `git clone` command to clone the repository:
   ```matlab
   git clone https://github.com/abhay-sah/CFmMIMO-SimDes.git
   ```

### 2. **Copy Required Helper Files**

1. Open the Matlab Example:
   ```matlab
   openExample('5g/EvaluatePerformanceOfCellFreemMIMONetworks')
   ```
2. Locate the following files:
   - `helperNRMetricsVisualizer.m`
   - `helperNetworkVisualizer.m`
   - `hMakeCustomCDL.m`
   - `hNRCustomChannelModel.m`
   - `hArrayGeometry.m`
     
3. Copy these files to the root directory of your cloned repository.

### 3. **Open the Project in MATLAB**

1. Navigate to the cloned repository directory in MATLAB.
2. Open the `Main.m` file and run it.

### 4. **Tweaking Parameters**

You can modify the following parameters within the `Pre6GCellFreeSimulationExample.mlx` file:

- **Area:** Adjust the simulation area size.
- **Number of APs:** Set the desired number of Access Points.
- **Number of UEs:** Specify the number of User Equipment.
- **Number of UE Connections:** Determine the number of connections per UE.
- **Number of Transmit and Receive Antennas:** Configure the antenna configurations for APs and UEs.
- **CPU, AP, and UE Configuration Parameters:** Modify the parameters related to CPU, AP, and UE resources and capabilities.

**Additional Tips:**

- **MATLAB Toolboxes:** Ensure you have the necessary MATLAB toolboxes installed, such as the 5G Toolbox and Communications Toolbox.
- **Runtime Environment:** Consider using a specific MATLAB Runtime Environment to package your simulation for deployment on other machines.
- **Debugging:** Utilize MATLAB's debugging tools to identify and fix issues if encounterd.

By following these steps and customizing the parameters, you can effectively run and analyze your cell-free simulations in MATLAB 2024b.

