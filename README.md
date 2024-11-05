# Exploiting Idempotently Monitored Methods for Faster Runtime Verification during Software Testing

## Appendix
See [appendix.pdf](appendix.pdf) for deIMM's overhead with code transformation time excluded, and the evolution experiment results.

## Projects and data
You can find the 65 projects and their revisions that we evaluate [here](data/projects/projects.txt). [This directory](data/classification) contains the
IMMs classification for these 65 projects, and [this directory](data/evolution) contains the raw data from the software evolution experiment.

## Repository structure
| Directory               | Purpose                                       |
| ------------------------| --------------------------------------------- |
| Docker                  | scripts to run our experiments in Docker      |
| data                    | raw data (see section above)                  |
| extensions              | a Maven extension to run JavaMOP              |
| mop                     | the set of JavaMOP specifications that we use |
| experiments             | deIMM and our experimental infrastructure     |
| scripts                 | scripts to locate and classify IMMs           |

## Usage
### Prerequisites:
- A x86-64 architecture machine
- Ubuntu 20.04
- [Docker](https://docs.docker.com/get-docker/)
### Setup
First, you need to build a Docker image. Run the following commands in terminal.
```sh
docker build -f Docker/Dockerfile . --tag=imm:latest
docker run -it --rm imm:latest
./setup.sh  # run this command in Docker container
```
Then, run the following command in a new terminal window.
```sh
docker ps  # get container id
docker commit <container-id> imm:latest
# You can now close the previous terminal window by entering `exit`
```

### Run single revision experiment
```sh
# Enter the following commands outside the Docker container and inside the current repository directory
cd Docker

# If you want to run deIMM on all projects (this could take multiple days), then run the below command. If you only want to test deIMM on one project (StarlangSoftware/TurkishWordNet), then skip the command below.
cp projects-all.txt projects.txt

# Run deIMM: 
bash e2e_experiment_in_docker.sh projects.txt ../data/classification/new-mixed-imm-all ../data/classification/new-output output false 86400s 86400s
```
#### Output
The above commands will generate an `output` directory. The `output` directory contains one sub-directory per project.
The `output/<project-name>/output/logs` directory contains multiple run logs. It also contains a time report `report.csv` file, and it has the following header:

```
test status,test time,mop status,mop time,imm process status,imm process time,imm mop status,imm mop time
```

Note that times are in milliseconds.
