pipeline {
    agent any
    
    parameters {
        choice(
            name: 'ENVIRONMENT',
            choices: ['prod', 'uat'],
            description: 'Select the environment to deploy'
        )
        choice(
            name: 'ACTION',
            choices: ['plan', 'apply', 'destroy'],
            description: 'Terraform action to perform'
        )
        booleanParam(
            name: 'AUTO_APPROVE',
            defaultValue: false,
            description: 'Auto approve terraform apply/destroy'
        )
        booleanParam(
            name: 'CLEAN_STATE',
            defaultValue: false,
            description: 'Clean state files (for subscription changes)'
        )
    }
    
    environment {
        TF_IN_AUTOMATION = 'true'
        PATH = "$PATH:$HOME/.local/bin"
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                echo "🚀 Deploying to environment: ${params.ENVIRONMENT}"
                echo "📋 Resource Group: srs-${params.ENVIRONMENT}-rg"
                echo "⚡ Terraform action: ${params.ACTION}"
            }
        }
        
        stage('Setup Terraform') {
            steps {
                script {
                    sh '''
                        if ! command -v terraform &> /dev/null; then
                            echo "📥 Installing Terraform..."
                            wget https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip
                            unzip terraform_1.5.7_linux_amd64.zip
                            chmod +x terraform
                            mkdir -p ~/.local/bin
                            mv terraform ~/.local/bin/
                            rm terraform_1.5.7_linux_amd64.zip
                            echo "✅ Terraform installed successfully"
                        else
                            echo "✅ Terraform is already installed"
                        fi
                        export PATH="$HOME/.local/bin:$PATH"
                        terraform version
                    '''
                }
            }
        }
        
        stage('Clean State for New Subscription') {
            when {
                expression { params.CLEAN_STATE == true }
            }
            steps {
                sh '''
                    echo "🧹 Cleaning old state files for subscription change..."
                    
                    # Remove old state files that point to old subscription
                    rm -f terraform.tfstate*
                    rm -f .terraform.lock.hcl
                    rm -rf .terraform/
                    
                    # Clean workspace-specific state files
                    rm -f terraform.tfstate.d/*/terraform.tfstate*
                    
                    echo "✅ State cleaned - ready for fresh deployment to new subscription"
                '''
            }
        }
        
        stage('Terraform Initialize') {
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        export PATH="$HOME/.local/bin:$PATH"
                        
                        echo "🔧 Initializing Terraform for new subscription..."
                        echo "🔐 Using secure Azure credentials from Jenkins vault"
                        
                        terraform init -upgrade -input=false
                        
                        echo "🏗️ Setting up workspace for environment: ${ENVIRONMENT}"
                        terraform workspace select ${ENVIRONMENT} || terraform workspace new ${ENVIRONMENT}
                        
                        CURRENT_WORKSPACE=$(terraform workspace show)
                        echo "✅ Current workspace: $CURRENT_WORKSPACE"
                        echo "📋 Target Resource Group: srs-${ENVIRONMENT}-rg"
                        
                        echo "📊 Available workspaces:"
                        terraform workspace list
                    '''
                }
            }
        }
        
        stage('Terraform Validate') {
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        export PATH="$HOME/.local/bin:$PATH"
                        
                        echo "✅ Validating Terraform configuration..."
                        terraform fmt
                        terraform validate
                        echo "✅ Configuration is valid for workspace: $(terraform workspace show)"
                    '''
                }
            }
        }
        
        stage('Terraform Plan') {
            when {
                anyOf {
                    expression { params.ACTION == 'plan' }
                    expression { params.ACTION == 'apply' }
                }
            }
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        export PATH="$HOME/.local/bin:$PATH"
                        
                        echo "📋 Planning Terraform deployment..."
                        echo "🎯 Environment: ${ENVIRONMENT}"
                        echo "📋 Resource Group: srs-${ENVIRONMENT}-rg"
                        echo "🏗️ Workspace: $(terraform workspace show)"
                        echo "🔐 Using secure Azure credentials"
                        
                        terraform plan \\
                          -var="environment=${ENVIRONMENT}" \\
                          -var="tenant_id=${ARM_TENANT_ID}" \\
                          -var="subscription_id=${ARM_SUBSCRIPTION_ID}" \\
                          -out=tfplan-${ENVIRONMENT}
                    '''
                    
                    archiveArtifacts artifacts: "tfplan-${params.ENVIRONMENT}", fingerprint: true, allowEmptyArchive: true
                }
            }
        }
        
        // ... rest of your existing stages (Apply, Destroy, Display Results, etc.)
    }
    
    // ... rest of your existing post section
}
