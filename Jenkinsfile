pipeline {
    agent any
    
    parameters {
        choice(
            name: 'ENVIRONMENT',
            choices: ['production', 'uat', 'dr'],
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
    }
    
    environment {
        TF_IN_AUTOMATION = 'true'
        PATH = "$PATH:$HOME/.local/bin"
        // Remove the TF_CLI_CONFIG_FILE line since .terraformrc doesn't exist
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                echo "Deploying to environment: ${params.ENVIRONMENT}"
                echo "Terraform action: ${params.ACTION}"
            }
        }
        
        stage('Setup Terraform') {
            steps {
                script {
                    sh '''
                        if ! command -v terraform &> /dev/null; then
                            echo "Installing Terraform..."
                            wget https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip
                            unzip terraform_1.5.7_linux_amd64.zip
                            chmod +x terraform
                            mkdir -p ~/.local/bin
                            mv terraform ~/.local/bin/
                            rm terraform_1.5.7_linux_amd64.zip
                            echo "Terraform installed successfully to ~/.local/bin/"
                        else
                            echo "Terraform is already installed"
                        fi
                        export PATH="$HOME/.local/bin:$PATH"
                        terraform version
                    '''
                }
            }
        }
        
        stage('Terraform Init') {
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        export PATH="$HOME/.local/bin:$PATH"
                        echo "Initializing Terraform..."
                        terraform init -upgrade -input=false
                    '''
                }
                // Archive state files for persistence
                script {
                    archiveArtifacts artifacts: 'terraform.tfstate*', fingerprint: true, allowEmptyArchive: true
                    archiveArtifacts artifacts: '.terraform.lock.hcl', fingerprint: true, allowEmptyArchive: true
                }
            }
        }
        
        stage('Restore State') {
            when {
                anyOf {
                    expression { params.ACTION == 'destroy' }
                    expression { params.ACTION == 'plan' }
                    expression { params.ACTION == 'apply' }
                }
            }
            steps {
                script {
                    // Try to restore previous state files
                    try {
                        copyArtifacts filter: 'terraform.tfstate*', fingerprintArtifacts: true, flatten: true, projectName: env.JOB_NAME, selector: lastSuccessful(), optional: true
                        copyArtifacts filter: '.terraform.lock.hcl', fingerprintArtifacts: true, flatten: true, projectName: env.JOB_NAME, selector: lastSuccessful(), optional: true
                        echo "State files restored from previous build"
                    } catch (Exception e) {
                        echo "No previous state files found or failed to restore: ${e.message}"
                    }
                }
            }
        }
        
        stage('Debug State Info') {
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        export PATH="$HOME/.local/bin:$PATH"
                        echo "=== Current Working Directory ==="
                        pwd
                        ls -la
                        
                        echo "=== Terraform State Info ==="
                        if [ -f "terraform.tfstate" ]; then
                            echo "Local state file exists"
                            terraform state list || echo "State file exists but no resources listed"
                        else
                            echo "No local state file found"
                        fi
                        
                        echo "=== Current Environment ==="
                        echo "Environment: ${ENVIRONMENT}"
                        echo "Action: ${ACTION}"
                        
                        echo "=== Check if Azure Resource Group Exists ==="
                        if command -v az &> /dev/null; then
                            az login --service-principal -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" --tenant "$ARM_TENANT_ID" > /dev/null 2>&1 || echo "Azure CLI login failed"
                            az group show --name "${ENVIRONMENT}-enterprise-rg" --query "name" -o tsv 2>/dev/null || echo "Resource group ${ENVIRONMENT}-enterprise-rg does not exist in Azure"
                        else
                            echo "Azure CLI not available for resource verification"
                        fi
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
                        echo "Formatting and validating Terraform configuration..."
                        terraform fmt
                        terraform validate
                    '''
                }
            }
        }
        
        stage('Import Existing Resources') {
            when {
                allOf {
                    expression { params.ACTION == 'destroy' }
                    expression {
                        def stateEmpty = sh(script: 'terraform state list | wc -l', returnStdout: true).trim() == '0'
                        return stateEmpty
                    }
                }
            }
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    script {
                        sh '''
                            export PATH="$HOME/.local/bin:$PATH"
                            
                            echo "Attempting to import existing resources..."
                            
                            # Check if resource group exists in Azure
                            az login --service-principal -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" --tenant "$ARM_TENANT_ID" > /dev/null 2>&1
                            
                            if az group show --name "${ENVIRONMENT}-enterprise-rg" >/dev/null 2>&1; then
                                echo "Resource group exists in Azure, attempting import..."
                                
                                # Import resource group
                                terraform import azurerm_resource_group.main "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/${ENVIRONMENT}-enterprise-rg" || echo "Failed to import resource group"
                                
                                # List what we have now
                                terraform state list
                                
                                echo "Import completed. Resources in state:"
                                terraform state list
                            else
                                echo "Resource group does not exist in Azure. Nothing to import."
                            fi
                        '''
                    }
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
                    script {
                        sh """
                            export PATH="\$HOME/.local/bin:\$PATH"
                            echo "Planning Terraform deployment for ${params.ENVIRONMENT}..."
                            terraform plan -var="environment=${params.ENVIRONMENT}" -out=tfplan-${params.ENVIRONMENT}
                        """
                        
                        // Archive the plan file
                        archiveArtifacts artifacts: "tfplan-${params.ENVIRONMENT}", fingerprint: true
                    }
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
                                echo "Applying Terraform configuration for ${params.ENVIRONMENT}..."
                                terraform apply -auto-approve -var="environment=${params.ENVIRONMENT}"
                            """
                        }
                    } else {
                        input message: "Approve Terraform Apply for ${params.ENVIRONMENT}?", ok: 'Apply'
                        withCredentials([
                            string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                            string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                            string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                            string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                        ]) {
                            sh """
                                export PATH="\$HOME/.local/bin:\$PATH"
                                echo "Applying Terraform configuration for ${params.ENVIRONMENT}..."
                                terraform apply -auto-approve -var="environment=${params.ENVIRONMENT}"
                            """
                        }
                    }
                }
                // Archive state after apply
                script {
                    archiveArtifacts artifacts: 'terraform.tfstate*', fingerprint: true, allowEmptyArchive: true
                }
            }
        }
        
        stage('Terraform Destroy') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                script {
                    input message: "⚠️ Are you sure you want to DESTROY ${params.ENVIRONMENT} infrastructure? This action cannot be undone!", ok: 'Destroy'
                    withCredentials([
                        string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                        string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                        string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                        string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                    ]) {
                        sh """
                            export PATH="\$HOME/.local/bin:\$PATH"
                            
                            echo "=== Current Terraform State ==="
                            terraform state list || echo "No resources in state"
                            
                            RESOURCE_COUNT=\$(terraform state list | wc -l)
                            
                            if [ "\$RESOURCE_COUNT" -eq 0 ]; then
                                echo "⚠️ No resources in Terraform state!"
                                
                                # Check if resources exist in Azure
                                az login --service-principal -u "\$ARM_CLIENT_ID" -p "\$ARM_CLIENT_SECRET" --tenant "\$ARM_TENANT_ID" > /dev/null 2>&1
                                
                                if az group show --name "${params.ENVIRONMENT}-enterprise-rg" >/dev/null 2>&1; then
                                    echo "🔍 Resources exist in Azure but not in Terraform state!"
                                    echo "Resources were imported earlier, refreshing state..."
                                    
                                    terraform refresh -var="environment=${params.ENVIRONMENT}"
                                    
                                    # Try destroy again
                                    echo "Attempting destroy with refreshed state..."
                                    terraform destroy -auto-approve -var="environment=${params.ENVIRONMENT}"
                                else
                                    echo "✅ No resources found in Azure either. Nothing to destroy."
                                fi
                            else
                                echo "🗑️ Destroying \$RESOURCE_COUNT resources for ${params.ENVIRONMENT}..."
                                terraform destroy -auto-approve -var="environment=${params.ENVIRONMENT}"
                            fi
                            
                            echo "=== Final State Check ==="
                            terraform state list || echo "State is now empty"
                        """
                    }
                }
            }
        }
        
        stage('Output Results') {
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
                        
                        echo "==========================================="
                        echo "🎉 DEPLOYMENT SUCCESSFUL!"
                        echo "==========================================="
                        
                        echo "=== 🔐 VM CREDENTIALS ==="
                        echo "Username: azureadmin"
                        echo -n "Password: "
                        terraform output -json resource_summary | grep -o '"admin_password":"[^"]*"' | cut -d'"' -f4
                        
                        echo ""
                        echo "=== 🌐 VM PUBLIC IPs ==="
                        terraform output vm_public_ips
                        
                        echo ""
                        echo "=== 🔒 VM PRIVATE IPs ==="
                        terraform output vm_private_ips
                        
                        echo ""
                        echo "=== 📋 INFRASTRUCTURE SUMMARY ==="
                        terraform output resource_summary | grep -v "sensitive" || echo "Full summary is marked as sensitive"
                        
                        echo ""
                        echo "=== 🎯 QUICK ACCESS COMMANDS ==="
                        echo "RDP to Application Server:"
                        terraform output -json vm_public_ips | grep -o '"uat-app":"[^"]*"' | cut -d'"' -f4 | xargs -I {} echo "mstsc /v:{}"
                        
                        echo ""
                        echo "RDP to Database Server:"
                        terraform output -json vm_public_ips | grep -o '"uat-db":"[^"]*"' | cut -d'"' -f4 | xargs -I {} echo "mstsc /v:{}"
                        
                        echo "==========================================="
                    '''
                }
            }
        }
    }
    
    post {
        always {
            script {
                // Archive final state
                archiveArtifacts artifacts: 'terraform.tfstate*', fingerprint: true, allowEmptyArchive: true
                archiveArtifacts artifacts: '.terraform.lock.hcl', fingerprint: true, allowEmptyArchive: true
                
                // Only clean workspace if it's a destroy action that completed successfully
                if (params.ACTION == 'destroy' && currentBuild.currentResult == 'SUCCESS') {
                    echo "🧹 Cleaning workspace after successful destroy"
                    cleanWs()
                } else {
                    echo "📁 Preserving workspace to maintain state files"
                }
            }
        }
        success {
            script {
                def actionEmoji = [
                    'plan': '📋',
                    'apply': '✅', 
                    'destroy': '🗑️'
                ]
                echo "${actionEmoji[params.ACTION]} Terraform ${params.ACTION} completed successfully for ${params.ENVIRONMENT}!"
                
                if (params.ACTION == 'apply') {
                    echo "🔐 Check the console output above for VM credentials and IP addresses"
                }
            }
        }
        failure {
            script {
                def actionEmoji = [
                    'plan': '📋',
                    'apply': '❌',
                    'destroy': '💥'
                ]
                echo "${actionEmoji[params.ACTION]} Terraform ${params.ACTION} failed for ${params.ENVIRONMENT}!"
                echo "🔍 Check the logs above for detailed error information"
            }
        }
    }
}
