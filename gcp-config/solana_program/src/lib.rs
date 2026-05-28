use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, TokenAccount, MintTo};

declare_id!("TROPSe11Se11Se11Se11Se11Se11Se11Se11Se11Se1");

#[program]
pub mod unykorn_token_sale {
    use super::*;

    /// Initialize the sale configuration, setting the TROP token mint, treasury wallet, and conversion rate
    pub fn initialize_sale(
        ctx: Context<InitializeSale>,
        rate: u64, // Amount of TROP tokens (in 10^-6 decimals) received per lamport (or 10^-9 SOL)
    ) -> Result<()> {
        let config = &mut ctx.accounts.sale_config;
        config.admin = ctx.accounts.admin.key();
        config.trop_mint = ctx.accounts.trop_mint.key();
        config.treasury_vault = ctx.accounts.treasury_vault.key();
        config.rate = rate;
        config.is_active = true;

        msg!("Troptions Sale Config initialized successfully. Rate: {} TROP/Lamport", rate);
        Ok(())
    }

    /// Register a wallet address as compliant/vetted under Genius Act kyc rules
    pub fn register_vetted_buyer(
        ctx: Context<RegisterVettedBuyer>,
        buyer_address: Pubkey,
        compliance_hash: [u8; 32],
    ) -> Result<()> {
        let registry = &mut ctx.accounts.compliance_record;
        registry.buyer = buyer_address;
        registry.compliance_hash = compliance_hash;
        registry.is_vetted = true;
        registry.updated_at = Clock::get()?.unix_timestamp;

        msg!("Compliance: Wallet {} registered as KYC verified.", buyer_address);
        Ok(())
    }

    /// Purchase TROP tokens by sending SOL directly to the treasury wallet.
    /// Requires the buyer's wallet to be registered as vetted.
    pub fn purchase_trop_tokens(
        ctx: Context<PurchaseTropTokens>,
        payment_amount_lamports: u64,
    ) -> Result<()> {
        let config = &ctx.accounts.sale_config;
        require!(config.is_active, ErrorCode::SaleInactive);

        // 1. Verify KYC / Vetting compliance
        let compliance = &ctx.accounts.compliance_record;
        require!(compliance.is_vetted, ErrorCode::BuyerNotVetted);
        require!(compliance.buyer == ctx.accounts.buyer.key(), ErrorCode::BuyerMismatch);

        // 2. Transfer SOL from buyer to treasury vault
        let transfer_instruction = anchor_lang::solana_program::system_instruction::transfer(
            &ctx.accounts.buyer.key(),
            &config.treasury_vault,
            payment_amount_lamports,
        );
        anchor_lang::solana_program::program::invoke(
            &transfer_instruction,
            &[
                ctx.accounts.buyer.to_account_info(),
                ctx.accounts.treasury_vault.to_account_info(),
                ctx.accounts.system_program.to_account_info(),
            ],
        )?;

        // 3. Calculate TROP tokens to mint (Rate represents TROP per lamport)
        let token_amount = payment_amount_lamports
            .checked_mul(config.rate)
            .ok_or(ErrorCode::MathOverflow)?;

        // 4. Mint TROP tokens directly into the buyer's token account
        let cpi_accounts = MintTo {
            mint: ctx.accounts.trop_mint.to_account_info(),
            to: ctx.accounts.buyer_token_account.to_account_info(),
            authority: ctx.accounts.mint_authority.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        
        // Use signer seeds to sign CPI mint if authority is a PDA (Program Derived Address)
        let cpi_ctx = CpiContext::new(cpi_program, cpi_accounts);
        token::mint_to(cpi_ctx, token_amount)?;

        msg!("Token Purchase: Swapped {} lamports for {} TROP tokens.", payment_amount_lamports, token_amount);
        Ok(())
    }

    /// Toggle active state of token sale
    pub fn toggle_sale_state(ctx: Context<AdminControl>, is_active: bool) -> Result<()> {
        let config = &mut ctx.accounts.sale_config;
        require!(ctx.accounts.admin.key() == config.admin, ErrorCode::Unauthorized);
        config.is_active = is_active;
        msg!("Troptions Sale State toggled. Active: {}", is_active);
        Ok(())
    }
}

#[derive(Accounts)]
pub struct InitializeSale<'info> {
    #[account(init, payer = admin, space = 8 + 32 + 32 + 32 + 8 + 1)]
    pub sale_config: Account<'info, SaleConfig>,
    pub trop_mint: Account<'info, Mint>,
    /// CHECK: Treasury wallet that collects purchase funds
    pub treasury_vault: AccountInfo<'info>,
    #[account(mut)]
    pub admin: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct RegisterVettedBuyer<'info> {
    #[account(
        init_if_needed,
        payer = admin,
        space = 8 + 32 + 32 + 1 + 8,
        seeds = [b"compliance", buyer.key().as_ref()],
        bump
    )]
    pub compliance_record: Account<'info, ComplianceRecord>,
    /// CHECK: Buyer wallet being vetted
    pub buyer: AccountInfo<'info>,
    #[account(mut)]
    pub admin: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct PurchaseTropTokens<'info> {
    pub sale_config: Account<'info, SaleConfig>,
    #[account(
        seeds = [b"compliance", buyer.key().as_ref()],
        bump,
        constraint = compliance_record.is_vetted == true
    )]
    pub compliance_record: Account<'info, ComplianceRecord>,
    #[account(mut)]
    pub buyer: Signer<'info>,
    #[account(mut)]
    pub trop_mint: Account<'info, Mint>,
    #[account(mut)]
    pub buyer_token_account: Account<'info, TokenAccount>,
    /// CHECK: Treasury vault to receive funds
    #[account(mut, constraint = treasury_vault.key() == sale_config.treasury_vault)]
    pub treasury_vault: AccountInfo<'info>,
    /// CHECK: Mint authority for TROP token (must sign minting)
    pub mint_authority: AccountInfo<'info>,
    pub token_program: Program<'info, token::Token>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct AdminControl<'info> {
    #[account(mut)]
    pub sale_config: Account<'info, SaleConfig>,
    pub admin: Signer<'info>,
}

#[account]
pub struct SaleConfig {
    pub admin: Pubkey,
    pub trop_mint: Pubkey,
    pub treasury_vault: Pubkey,
    pub rate: u64,
    pub is_active: bool,
}

#[account]
pub struct ComplianceRecord {
    pub buyer: Pubkey,
    pub compliance_hash: [u8; 32],
    pub is_vetted: bool,
    pub updated_at: i64,
}

#[error_code]
pub mod ErrorCode {
    #[msg("The token sale is currently inactive.")]
    SaleInactive,
    #[msg("The buyer address is not KYC vetted in the compliance record.")]
    BuyerNotVetted,
    #[msg("The buyer public key does not match the compliance record.")]
    BuyerMismatch,
    #[msg("Unauthorized admin action.")]
    Unauthorized,
    #[msg("Mathematical calculation overflowed.")]
    MathOverflow,
}
