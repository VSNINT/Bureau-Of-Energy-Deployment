pipeline {
    agent any
    
    parameters {
        choice(
            name: 'ENVIRONMENT',
            choices: ['prod', 'uat'],
            description: 'Select the environment to deploy (DR removed)'
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
    }
    
    environment {
        TF_IN_AUTOMATION = 'true'
        PATH = "$PATH:$HOME/.local/bin"
        // New Azure tenant and subscription IDs
        AZURE_TENANT_ID = 'a59c2881-bb68-4882-b6d6-2b89b702e235'
        AZURE_SUBSCRIPTION_ID = 'f9eb7bb0-d778-4643-84ef-ce453b7dd896'
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                echo "🚀 Deploying to environment: ${params.ENVIRONMENT}"
                echo "📋 Resource Group: srs-${params.ENVIRONMENT}-rg"
                echo "⚡ Terraform action: ${params.ACTION}"
                echo "🏢 Tenant: ${env.AZURE_TENANT_ID}"
                echo "📋 Subscription: ${env.AZURE_SUBSCRIPTION_ID}"
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
        
        stage('Azure Authentication') {
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        echo "🧹 Clearing Azure authentication cache..."
                        
                        # Clear all cached tokens and sessions
                        az logout 2>/dev/null || echo "✅ Already logged out"
                        az account clear 2>/dev/null || echo "✅ Account cache already cleared"
                        az cache purge 2>/dev/null || echo "✅ CLI cache already cleared"
                        
                        # Remove any existing token files
                        rm -rf ~/.azure/accessTokens.json 2>/dev/null || echo "✅ No token files to remove"
                        rm -rf ~/.azure/azureProfile.json 2>/dev/null || echo "✅ No profile files to remove"
                        
                        echo "🔐 Authenticating with new Azure tenant..."
                        echo "🎯 Target Tenant: a59c2881-bb68-4882-b6d6-2b89b702e235"
                        echo "📋 Target Subscription: f9eb7bb0-d778-4643-84ef-ce453b7dd896"
                        
                        # Force fresh login to correct tenant
                        az login --service-principal \
                            --username "${ARM_CLIENT_ID}" \
                            --password "${ARM_CLIENT_SECRET}" \
                            --tenant "a59c2881-bb68-4882-b6d6-2b89b702e235"
                        
                        # Set correct subscription
                        az account set --subscription "f9eb7bb0-d778-4643-84ef-ce453b7dd896"
                        
                        # Verify authentication is correct
                        echo "✅ Authentication verification:"
                        CURRENT_TENANT=$(az account show --query "tenantId" -o tsv)
                        CURRENT_SUBSCRIPTION=$(az account show --query "id" -o tsv)
                        
                        echo "✅ Current Tenant: $CURRENT_TENANT"
                        echo "✅ Current Subscription: $CURRENT_SUBSCRIPTION"
                        
                        # Validate we're in the right tenant/subscription
                        if [ "$CURRENT_TENANT" = "a59c2881-bb68-4882-b6d6-2b89b702e235" ]; then
                            echo "✅ Tenant authentication SUCCESS!"
                        else
                            echo "❌ Tenant mismatch! Expected: a59c2881-bb68-4882-b6d6-2b89b702e235, Got: $CURRENT_TENANT"
                            exit 1
                        fi
                        
                        if [ "$CURRENT_SUBSCRIPTION" = "f9eb7bb0-d778-4643-84ef-ce453b7dd896" ]; then
                            echo "✅ Subscription authentication SUCCESS!"
                        else
                            echo "❌ Subscription mismatch! Expected: f9eb7bb0-d778-4643-84ef-ce453b7dd896, Got: $CURRENT_SUBSCRIPTION"
                            exit 1
                        fi
                        
                        echo "🎉 Azure authentication completed successfully!"
                    '''
                }
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
                        
                        # Override with correct tenant/subscription
                        export ARM_TENANT_ID="a59c2881-bb68-4882-b6d6-2b89b702e235"
                        export ARM_SUBSCRIPTION_ID="f9eb7bb0-d778-4643-84ef-ce453b7dd896"
                        
                        echo "🔧 Initializing Terraform..."
                        terraform init -upgrade -input=false -migrate-state
                        
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
                        
                        # Override with correct tenant/subscription
                        export ARM_TENANT_ID="a59c2881-bb68-4882-b6d6-2b89b702e235"
                        export ARM_SUBSCRIPTION_ID="f9eb7bb0-d778-4643-84ef-ce453b7dd896"
                        
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
                    sh """
                        export PATH="\$HOME/.local/bin:\$PATH"
                        
                        # Override with correct tenant/subscription
                        export ARM_TENANT_ID="a59c2881-bb68-4882-b6d6-2b89b702e235"
                        export ARM_SUBSCRIPTION_ID="f9eb7bb0-d778-4643-84ef-ce453b7dd896"
                        
                        echo "📋 Planning Terraform deployment..."
                        echo "🎯 Environment: ${params.ENVIRONMENT}"
                        echo "📋 Resource Group: srs-${params.ENVIRONMENT}-rg"
                        echo "🏗️ Workspace: \$(terraform workspace show)"
                        echo "🏢 Tenant: a59c2881-bb68-4882-b6d6-2b89b702e235"
                        echo "📋 Subscription: f9eb7bb0-d778-4643-84ef-ce453b7dd896"
                        
                        terraform plan -var="environment=${params.ENVIRONMENT}" -out=tfplan-${params.ENVIRONMENT}
                    """
                    
                    archiveArtifacts artifacts: "tfplan-${params.ENVIRONMENT}", fingerprint: true, allowEmptyArchive: true
                }
            }
        }
        
        stage('Terraform Apply') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                script {
                    if (params.AUTO_APPROVE) {
                        withCredentials([
                            string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                            string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                            string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                            string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                        ]) {
                            sh """
                                export PATH="\$HOME/.local/bin:\$PATH"
                                
                                # Override with correct tenant/subscription
                                export ARM_TENANT_ID="a59c2881-bb68-4882-b6d6-2b89b702e235"
                                export ARM_SUBSCRIPTION_ID="f9eb7bb0-d778-4643-84ef-ce453b7dd896"
                                
                                echo "🚀 Applying Terraform configuration..."
                                echo "🎯 Environment: ${params.ENVIRONMENT}"
                                echo "📋 Resource Group: srs-${params.ENVIRONMENT}-rg"
                                echo "🏗️ Workspace: \$(terraform workspace show)"
                                
                                terraform apply -auto-approve -var="environment=${params.ENVIRONMENT}"
                            """
                        }
                    } else {
                        input message: "🚀 Approve Terraform Apply for ${params.ENVIRONMENT} environment?", ok: 'Apply'
                        withCredentials([
                            string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                            string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                            string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                            string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                        ]) {
                            sh """
                                export PATH="\$HOME/.local/bin:\$PATH"
                                
                                # Override with correct tenant/subscription
                                export ARM_TENANT_ID="a59c2881-bb68-4882-b6d6-2b89b702e235"
                                export ARM_SUBSCRIPTION_ID="f9eb7bb0-d778-4643-84ef-ce453b7dd896"
                                
                                echo "🚀 Applying Terraform configuration..."
                                echo "🎯 Environment: ${params.ENVIRONMENT}"
                                echo "📋 Resource Group: srs-${params.ENVIRONMENT}-rg"
                                echo "🏗️ Workspace: \$(terraform workspace show)"
                                
                                terraform apply -auto-approve -var="environment=${params.ENVIRONMENT}"
                            """
                        }
                    }
                }
            }
        }
        
        stage('Terraform Destroy') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                script {
                    input message: "⚠️ DANGER: Destroy ${params.ENVIRONMENT} environment and srs-${params.ENVIRONMENT}-rg? This cannot be undone!", ok: 'Destroy'
                    withCredentials([
                        string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                        string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                        string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                        string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                    ]) {
                        sh '''
                            export PATH="$HOME/.local/bin:$PATH"
                            
                            # Override with correct tenant/subscription
                            export ARM_TENANT_ID="a59c2881-bb68-4882-b6d6-2b89b702e235"
                            export ARM_SUBSCRIPTION_ID="f9eb7bb0-d778-4643-84ef-ce453b7dd896"
                            
                            echo "🗑️ === CLEAN DESTROY OPERATION ==="
                            echo "🎯 Environment: ${ENVIRONMENT}"
                            echo "📋 Resource Group: srs-${ENVIRONMENT}-rg"
                            echo "🏗️ Workspace: $(terraform workspace show)"
                            echo "🏢 Tenant: a59c2881-bb68-4882-b6d6-2b89b702e235"
                            echo "📋 Subscription: f9eb7bb0-d778-4643-84ef-ce453b7dd896"
                            
                            RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l)
                            echo "📊 Resources in workspace state: $RESOURCE_COUNT"
                            
                            if [ "$RESOURCE_COUNT" -gt 0 ]; then
                                echo "🗂️ Resources to be destroyed:"
                                terraform state list
                                echo ""
                                echo "🗑️ Destroying all resources in srs-${ENVIRONMENT}-rg..."
                                
                                # Simple destroy - no shared resources to worry about!
                                terraform destroy -auto-approve -var="environment=${ENVIRONMENT}"
                                
                                echo "✅ Destroy operation completed!"
                                echo "📋 Resource Group srs-${ENVIRONMENT}-rg and all contents destroyed"
                            else
                                echo "ℹ️ No resources found in Terraform state"
                                echo "✅ Nothing to destroy"
                            fi
                        '''
                    }
                }
            }
        }
        
        stage('Display Results') {
            when {
                expression { params.ACTION == 'apply' }
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
                        
                        # Override with correct tenant/subscription
                        export ARM_TENANT_ID="a59c2881-bb68-4882-b6d6-2b89b702e235"
                        export ARM_SUBSCRIPTION_ID="f9eb7bb0-d778-4643-84ef-ce453b7dd896"
                        
                        echo ""
                        echo "=========================================="
                        echo "🎉 DEPLOYMENT SUCCESSFUL!"
                        echo "=========================================="
                        echo "🎯 Environment: ${ENVIRONMENT}"
                        echo "📋 Resource Group: srs-${ENVIRONMENT}-rg"
                        echo "🏗️ Workspace: $(terraform workspace show)"
                        echo "🏢 Tenant: a59c2881-bb68-4882-b6d6-2b89b702e235"
                        echo "📋 Subscription: f9eb7bb0-d778-4643-84ef-ce453b7dd896"
                        echo ""
                        
                        echo "🔐 === VM CREDENTIALS ==="
                        echo "👤 Username: azureadmin"
                        PASSWORD=$(terraform output -raw admin_password 2>/dev/null || echo "Password not available")
                        echo "🔑 Password: [${PASSWORD}]"
                        echo ""
                        
                        echo "🌐 === PUBLIC IP ADDRESSES ==="
                        terraform output vm_public_ips
                        echo ""
                        
                        echo "🔒 === PRIVATE IP ADDRESSES ==="
                        terraform output vm_private_ips
                        echo ""
                        
                        echo "🎯 === QUICK RDP COMMANDS ==="
                        APP_IP=$(terraform output -json vm_public_ips | grep -o '"'${ENVIRONMENT}'-app":"[^"]*"' | cut -d'"' -f4)
                        DB_IP=$(terraform output -json vm_public_ips | grep -o '"'${ENVIRONMENT}'-db":"[^"]*"' | cut -d'"' -f4)
                        
                        if [ ! -z "$APP_IP" ]; then
                            echo "Application Server: mstsc /v:$APP_IP"
                        fi
                        if [ ! -z "$DB_IP" ]; then
                            echo "Database Server: mstsc /v:$DB_IP"
                        fi
                        echo ""
                        echo "=========================================="
                        echo "📊 DEPLOYMENT SUMMARY:"
                        echo "Environment: ${ENVIRONMENT}"
                        echo "Resource Group: srs-${ENVIRONMENT}-rg"
                        echo "Resources: $(terraform state list 2>/dev/null | wc -l)"
                        echo "Tenant: a59c2881-bb68-4882-b6d6-2b89b702e235"
                        echo "Subscription: f9eb7bb0-d778-4643-84ef-ce453b7dd896"
                        echo "=========================================="
                    '''
                }
            }
        }
    }
    
    post {
        always {
            script {
                echo "🗃️ Archiving state files for workspace: ${params.ENVIRONMENT}"
                archiveArtifacts artifacts: 'terraform.tfstate*', fingerprint: true, allowEmptyArchive: true
                archiveArtifacts artifacts: '.terraform.lock.hcl', fingerprint: true, allowEmptyArchive: true
                archiveArtifacts artifacts: "tfplan-${params.ENVIRONMENT}", fingerprint: true, allowEmptyArchive: true
                
                if (params.ACTION == 'destroy' && currentBuild.currentResult == 'SUCCESS') {
                    echo "🧹 Cleaning workspace after successful destroy of ${params.ENVIRONMENT}"
                    cleanWs()
                } else {
                    echo "📁 Preserving workspace files for ${params.ENVIRONMENT} environment"
                }
            }
        }
        success {
            script {
                def actionEmoji = ['plan': '📋', 'apply': '✅', 'destroy': '🗑️']
                echo "${actionEmoji[params.ACTION]} Terraform ${params.ACTION} completed successfully!"
                echo "🎯 Environment: ${params.ENVIRONMENT}"
                echo "📋 Resource Group: srs-${params.ENVIRONMENT}-rg"
                echo "🏢 Tenant: a59c2881-bb68-4882-b6d6-2b89b702e235"
                echo "📋 Subscription: f9eb7bb0-d778-4643-84ef-ce453b7dd896"
                
                if (params.ACTION == 'destroy') {
                    echo "🗑️ Complete environment cleanup - no shared resources left behind!"
                }
            }
        }
        failure {
            script {
                def actionEmoji = ['plan': '📋', 'apply': '❌', 'destroy': '💥']
                echo "${actionEmoji[params.ACTION]} Terraform ${params.ACTION} failed!"
                echo "🎯 Environment: ${params.ENVIRONMENT}"
                echo "📋 Resource Group: srs-${params.ENVIRONMENT}-rg"
                echo "🏢 Tenant: a59c2881-bb68-4882-b6d6-2b89b702e235"
                echo "📋 Subscription: f9eb7bb0-d778-4643-84ef-ce453b7dd896"
                echo "🔍 Check the logs above for error details"
            }
        }
    }
}
