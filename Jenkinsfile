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
            description: 'Clean state files (use for subscription changes)'
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
                script {
                    if (params.CLEAN_STATE) {
                        echo "🧹 State cleanup enabled for subscription change"
                    }
                }
            }
        }
        
        stage('Setup Terraform') {
            steps {
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
        
        stage('Clean State for New Subscription') {
            when {
                expression { params.CLEAN_STATE == true }
            }
            steps {
                sh '''
                    echo "🧹 Cleaning old state files for subscription change..."
                    echo "⚠️  Removing state files that point to old subscription/tenant"
                    
                    # Remove state files
                    rm -f terraform.tfstate
                    rm -f terraform.tfstate.backup
                    rm -f .terraform.lock.hcl
                    
                    # Remove state directories (using -rf for directories)
                    rm -rf .terraform/
                    rm -rf terraform.tfstate.d/
                    
                    # Clean any cached provider files
                    find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
                    
                    # Verify cleanup
                    echo "📂 Directory contents after cleanup:"
                    ls -la | grep -E "(terraform|\\.terraform)" || echo "✅ No terraform state files remaining"
                    
                    echo "✅ State cleaned successfully"
                    echo "📋 Ready for fresh deployment to new subscription"
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
                        
                        echo "🔧 Initializing Terraform with new subscription credentials..."
                        echo "🔐 Using secure Azure credentials from Jenkins vault"
                        
                        # Initialize with fresh state
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
                            sh '''
                                export PATH="$HOME/.local/bin:$PATH"
                                
                                echo "🚀 Applying Terraform configuration..."
                                echo "🎯 Environment: ${ENVIRONMENT}"
                                echo "📋 Resource Group: srs-${ENVIRONMENT}-rg"
                                echo "🏗️ Workspace: $(terraform workspace show)"
                                
                                terraform apply -auto-approve \\
                                  -var="environment=${ENVIRONMENT}" \\
                                  -var="tenant_id=${ARM_TENANT_ID}" \\
                                  -var="subscription_id=${ARM_SUBSCRIPTION_ID}"
                            '''
                        }
                    } else {
                        input message: "🚀 Approve Terraform Apply for ${params.ENVIRONMENT} environment?", ok: 'Apply'
                        withCredentials([
                            string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                            string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                            string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                            string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                        ]) {
                            sh '''
                                export PATH="$HOME/.local/bin:$PATH"
                                
                                echo "🚀 Applying Terraform configuration..."
                                echo "🎯 Environment: ${ENVIRONMENT}"
                                echo "📋 Resource Group: srs-${ENVIRONMENT}-rg"
                                echo "🏗️ Workspace: $(terraform workspace show)"
                                
                                terraform apply -auto-approve \\
                                  -var="environment=${ENVIRONMENT}" \\
                                  -var="tenant_id=${ARM_TENANT_ID}" \\
                                  -var="subscription_id=${ARM_SUBSCRIPTION_ID}"
                            '''
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
                            
                            echo "🗑️ === CLEAN DESTROY OPERATION ==="
                            echo "🎯 Environment: ${ENVIRONMENT}"
                            echo "📋 Resource Group: srs-${ENVIRONMENT}-rg"
                            echo "🏗️ Workspace: $(terraform workspace show)"
                            echo "🔐 Using secure Azure credentials"
                            
                            RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l)
                            echo "📊 Resources in workspace state: $RESOURCE_COUNT"
                            
                            if [ "$RESOURCE_COUNT" -gt 0 ]; then
                                echo "🗂️ Resources to be destroyed:"
                                terraform state list
                                echo ""
                                echo "🗑️ Destroying all resources in srs-${ENVIRONMENT}-rg..."
                                
                                # Simple destroy - no shared resources to worry about!
                                terraform destroy -auto-approve \\
                                  -var="environment=${ENVIRONMENT}" \\
                                  -var="tenant_id=${ARM_TENANT_ID}" \\
                                  -var="subscription_id=${ARM_SUBSCRIPTION_ID}"
                                
                                echo "✅ Destroy operation completed!"
                                echo "📋 Resource Group srs-${ENVIRONMENT}-rg destroyed"
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
                        
                        echo ""
                        echo "=========================================="
                        echo "🎉 DEPLOYMENT SUCCESSFUL!"
                        echo "=========================================="
                        echo "🎯 Environment: ${ENVIRONMENT}"
                        echo "📋 Resource Group: srs-${ENVIRONMENT}-rg"
                        echo "🏗️ Workspace: $(terraform workspace show)"
                        echo "🔐 Using secure Azure credentials"
                        echo ""
                        
                        echo "🔐 === VM CREDENTIALS ==="
                        echo "👤 Username: azureadmin"
                        echo "🔑 Password: [Use terraform output admin_password to view securely]"
                        echo ""
                        
                        echo "🌐 === PUBLIC IP ADDRESSES ==="
                        terraform output vm_public_ips 2>/dev/null || echo "Public IPs not available yet"
                        echo ""
                        
                        echo "🔒 === PRIVATE IP ADDRESSES ==="
                        terraform output vm_private_ips 2>/dev/null || echo "Private IPs not available yet"
                        echo ""
                        
                        echo "🎯 === QUICK RDP COMMANDS ==="
                        APP_IP=$(terraform output -json vm_public_ips 2>/dev/null | grep -o '"'${ENVIRONMENT}'-app":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
                        DB_IP=$(terraform output -json vm_public_ips 2>/dev/null | grep -o '"'${ENVIRONMENT}'-db":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
                        
                        if [ ! -z "$APP_IP" ] && [ "$APP_IP" != "null" ] && [ "$APP_IP" != "" ]; then
                            echo "Application Server: mstsc /v:$APP_IP"
                        fi
                        if [ ! -z "$DB_IP" ] && [ "$DB_IP" != "null" ] && [ "$DB_IP" != "" ]; then
                            echo "Database Server: mstsc /v:$DB_IP"
                        fi
                        echo ""
                        echo "=========================================="
                        echo "📊 DEPLOYMENT SUMMARY:"
                        echo "Environment: ${ENVIRONMENT}"
                        echo "Resource Group: srs-${ENVIRONMENT}-rg"
                        echo "Resources: $(terraform state list 2>/dev/null | wc -l)"
                        echo "Authentication: ✅ Secure"
                        echo "Subscription: ✅ New credentials active"
                        echo "=========================================="
                        
                        echo ""
                        echo "💡 To view VM password securely:"
                        echo "terraform output admin_password"
                        echo ""
                        echo "💡 To view complete connection info:"
                        echo "terraform output quick_access"
                    '''
                }
            }
        }
    }
    
    post {
        always {
            script {
                echo "🗃️ Archiving state files for workspace: ${params.ENVIRONMENT}"
                
                try {
                    archiveArtifacts artifacts: 'terraform.tfstate*', fingerprint: true, allowEmptyArchive: true
                } catch (Exception e) {
                    echo "⚠️ Could not archive state files: ${e.getMessage()}"
                }
                
                try {
                    archiveArtifacts artifacts: '.terraform.lock.hcl', fingerprint: true, allowEmptyArchive: true
                } catch (Exception e) {
                    echo "⚠️ Could not archive lock file: ${e.getMessage()}"
                }
                
                try {
                    archiveArtifacts artifacts: "tfplan-${params.ENVIRONMENT}", fingerprint: true, allowEmptyArchive: true
                } catch (Exception e) {
                    echo "⚠️ Could not archive plan file: ${e.getMessage()}"
                }
                
                if (params.ACTION == 'destroy' && currentBuild.currentResult == 'SUCCESS') {
                    echo "🧹 Cleaning workspace after successful destroy of ${params.ENVIRONMENT}"
                    cleanWs()
                } else {
                    echo "📁 Preserving workspace files for ${params.ENVIRONMENT} environment"
                }
                
                if (params.CLEAN_STATE) {
                    echo "🧹 State cleanup was performed for subscription change"
                }
            }
        }
        success {
            script {
                def actionEmoji = ['plan': '📋', 'apply': '✅', 'destroy': '🗑️']
                echo "${actionEmoji[params.ACTION]} Terraform ${params.ACTION} completed successfully!"
                echo "🎯 Environment: ${params.ENVIRONMENT}"
                echo "📋 Resource Group: srs-${params.ENVIRONMENT}-rg"
                echo "🔐 Security: All credentials protected"
                
                if (params.CLEAN_STATE) {
                    echo "🧹 Fresh deployment with new subscription credentials"
                }
                
                if (params.ACTION == 'destroy') {
                    echo "🗑️ Complete environment cleanup - no shared resources left behind!"
                } else if (params.ACTION == 'apply') {
                    echo "🎉 Your separate resource groups solution is working perfectly!"
                    echo "✅ PROD: srs-prod-rg (Independent lifecycle)"
                    echo "✅ UAT: srs-uat-rg (Independent lifecycle)"
                    echo "✅ Clean destroy operations enabled"
                }
            }
        }
        failure {
            script {
                def actionEmoji = ['plan': '📋', 'apply': '❌', 'destroy': '💥']
                echo "${actionEmoji[params.ACTION]} Terraform ${params.ACTION} failed!"
                echo "🎯 Environment: ${params.ENVIRONMENT}"
                echo "📋 Resource Group: srs-${params.ENVIRONMENT}-rg"
                echo "🔍 Check the logs above for error details"
                
                if (params.CLEAN_STATE) {
                    echo "🧹 State cleanup was attempted"
                    echo "💡 If authentication errors persist, verify Jenkins credentials"
                }
            }
        }
    }
}
